//! C ABI used by the Flutter UI (`macndowsfan_core.dll`).

use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::time::{Duration, Instant};

use serde_json::json;

use crate::config::{self, ControlMode, Settings};
use crate::machine::{Machine, Snapshot};

pub struct MfHandle {
    machine: Option<Machine>,
    settings: Settings,
    error: Option<String>,
    hint: Option<String>,
    last_sensor_refresh: Option<Instant>,
    needs_restore: bool,
}

fn to_c(v: serde_json::Value) -> *mut c_char {
    let text = v.to_string();
    match CString::new(text) {
        Ok(c) => c.into_raw(),
        Err(_) => CString::new("{\"ok\":false,\"error\":\"NUL in JSON\"}")
            .expect("static")
            .into_raw(),
    }
}

fn err_value(error: &Option<String>, hint: &Option<String>) -> serde_json::Value {
    json!({
        "ok": false,
        "error": error,
        "hint": hint,
        "modeStyle": null,
        "keyCount": null,
        "updatedMs": 0,
        "fans": [],
        "temps": [],
    })
}

fn snapshot_to_json(s: &Snapshot) -> serde_json::Value {
    json!({
                "ok": s.error.is_none(),
                "error": &s.error,
                "hint": &s.error_hint,
                "modeStyle": &s.mode_style,
                "keyCount": s.key_count,
                "updatedMs": s.updated_ms,
                "fans": s.fans.iter().map(|f| json!({
                    "index": f.index,
                    "name": &f.name,
                    "actual": f.actual,
                    "target": f.target,
                    "minRpm": f.min_rpm,
                    "maxRpm": f.max_rpm,
                    "forced": f.forced,
                    "controllable": f.controllable,
                    "valueType": &f.value_type,
                    "modeKey": &f.mode_key,
                })).collect::<Vec<_>>(),
                "temps": s.temps.iter().map(|t| json!({
                    "key": &t.key,
                    "label": &t.label,
                    "value": t.value,
                })).collect::<Vec<_>>(),
    })
}

fn snapshot_value(h: &MfHandle) -> serde_json::Value {
    match &h.machine {
        Some(m) => {
            let mut snap = m.sample();
            if h.needs_restore {
                snap.error = Some(h.error.clone().unwrap_or_else(||
                    "Cannot confirm automatic fan control".to_string()));
                snap.error_hint = h.hint.clone();
            }
            snapshot_to_json(&snap)
        }
        None => err_value(&h.error, &h.hint),
    }
}

fn set_error(h: &mut MfHandle, e: &crate::smc::SmcError) {
    h.error = Some(e.to_string());
    let hint = e.hint();
    h.hint = if hint.is_empty() {
        None
    } else {
        Some(hint.to_string())
    };
}

/// Create a handle. The handle is always valid; inspect `ok`/`error` in the
/// sample JSON to see whether the SMC could be opened.
#[no_mangle]
pub extern "C" fn mf_create() -> *mut MfHandle {
    let mut handle = Box::new(MfHandle {
        machine: None,
        settings: config::load(),
        error: None,
        hint: None,
        last_sensor_refresh: None,
        needs_restore: false,
    });
    match Machine::open() {
        Ok(m) => {
            handle.machine = Some(m);
            config::log("core: SMC connected");
        }
        Err(e) => {
            config::log(&format!("core: SMC open failed: {e}"));
            set_error(&mut handle, &e);
        }
    }
    Box::into_raw(handle)
}

#[no_mangle]
pub extern "C" fn mf_destroy(h: *mut MfHandle) {
    if !h.is_null() {
        unsafe {
            drop(Box::from_raw(h));
        }
    }
}

#[no_mangle]
pub extern "C" fn mf_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            drop(CString::from_raw(s));
        }
    }
}

#[no_mangle]
pub extern "C" fn mf_version() -> *mut c_char {
    to_c(json!({
        "version": env!("CARGO_PKG_VERSION"),
        "name": "macndowsfan core",
    }))
}

/// Try to reopen the SMC device and return a fresh snapshot.
#[no_mangle]
pub extern "C" fn mf_reconnect(h: *mut MfHandle) -> *mut c_char {
    if h.is_null() {
        return to_c(json!({"ok": false, "error": "null handle"}));
    }
    let h = unsafe { &mut *h };
    // A broken handle may be unable to restore control. Close it so the
    // exclusive device can be reopened, then retry restoration on the new
    // handle before any saved profile is applied.
    if let Some(machine) = h.machine.as_mut() {
        if let Err(e) = machine.restore_auto() {
            config::log(&format!("restore before reconnect failed: {e}"));
        }
    }
    h.machine = None;
    h.needs_restore = true;
    match Machine::open() {
        Ok(mut machine) => {
            let restore = machine.restore_auto();
            h.machine = Some(machine);
            h.last_sensor_refresh = None;
            if let Err(e) = restore {
                set_error(h, &e);
                return to_c(err_value(&h.error, &h.hint));
            }
            h.needs_restore = false;
            h.error = None;
            h.hint = None;
            to_c(snapshot_value(h))
        }
        Err(e) => {
            set_error(h, &e);
            h.error = Some(format!("{e}; cannot confirm automatic fan control"));
            to_c(err_value(&h.error, &h.hint))
        }
    }
}

#[no_mangle]
pub extern "C" fn mf_sample(h: *const MfHandle) -> *mut c_char {
    if h.is_null() {
        return to_c(json!({"ok": false, "error": "null handle"}));
    }
    let h = unsafe { &*h };
    to_c(snapshot_value(h))
}

/// One control tick: sample temperatures, apply the stored profile and return
/// a fresh snapshot. The Flutter UI calls this once per second so Sensor-based
/// curves actually track temperature changes.
#[no_mangle]
pub extern "C" fn mf_tick(h: *mut MfHandle) -> *mut c_char {
    if h.is_null() {
        return to_c(json!({"ok": false, "error": "null handle"}));
    }
    let h = unsafe { &mut *h };
    if h.machine.is_none() {
        return to_c(snapshot_value(h));
    }
    if h.needs_restore {
        if let Err(e) = ensure_restored(h) {
            set_error(h, &e);
            let mut snapshot = h.machine.as_ref().expect("checked above").sample();
            snapshot.error = h.error.clone();
            snapshot.error_hint = h.hint.clone();
            return to_c(snapshot_to_json(&snapshot));
        }
    }

    let mut failure: Option<crate::smc::SmcError> = None;
    let settings = h.settings.clone();
    let refresh = h.last_sensor_refresh.map_or(true, |t| t.elapsed() >= Duration::from_secs(10));
    let mut snapshot = {
        let machine = h.machine.as_mut().expect("checked above");
        if refresh {
            machine.refresh_sensors();
            h.last_sensor_refresh = Some(Instant::now());
        }
        let snap = machine.sample();
        let temps: HashMap<String, f32> = snap
            .temps
            .iter()
            .filter_map(|t| t.value.map(|v| (t.key.clone(), v)))
            .collect();

        match machine.apply(&settings, &temps) {
            Ok(actions) => {
                for action in &actions {
                    config::log(action);
                }
            }
            Err(e) => failure = Some(e),
        }
        snap
    };

    if let Some(e) = failure {
        config::log(&format!("tick apply failed: {e}"));
        set_error(h, &e);
        if let Err(restore_error) = ensure_restored(h) {
            config::log(&format!("restore after tick failure failed: {restore_error}"));
            h.error = Some(format!("{e}; restore automatic failed: {restore_error}"));
        }
        snapshot.error = h.error.clone();
        snapshot.error_hint = h.hint.clone();
        return to_c(snapshot_to_json(&snapshot));
    }

    to_c(snapshot_to_json(&snapshot))
}

#[no_mangle]
pub extern "C" fn mf_get_settings(h: *const MfHandle) -> *mut c_char {
    if h.is_null() {
        return to_c(json!({"fans": []}));
    }
    let h = unsafe { &*h };
    match serde_json::to_value(&h.settings) {
        Ok(v) => to_c(v),
        Err(e) => to_c(json!({"error": e.to_string(), "fans": []})),
    }
}

/// Apply a full settings document (same JSON shape as settings.json).
#[no_mangle]
pub extern "C" fn mf_apply(h: *mut MfHandle, settings_json: *const c_char) -> *mut c_char {
    if h.is_null() || settings_json.is_null() {
        return to_c(json!({"ok": false, "error": "null argument"}));
    }
    let h = unsafe { &mut *h };
    let text = match unsafe { CStr::from_ptr(settings_json) }.to_str() {
        Ok(t) => t,
        Err(e) => return to_c(json!({"ok": false, "error": format!("invalid UTF-8: {e}")})),
    };
    let settings: Settings = match serde_json::from_str(text) {
        Ok(s) => s,
        Err(e) => {
            return to_c(json!({
                "ok": false,
                "error": format!("invalid settings JSON: {e}"),
            }))
        }
    };

    h.settings = settings.clone();
    config::save(&settings);

    if h.machine.is_none() {
        return to_c(snapshot_value(h));
    }
    if h.needs_restore {
        if let Err(e) = ensure_restored(h) {
            set_error(h, &e);
            return to_c(snapshot_value(h));
        }
    }
    let Some(machine) = h.machine.as_mut() else {
        return to_c(err_value(&h.error, &h.hint));
    };

    let snap = machine.sample();
    let temps: HashMap<String, f32> = snap
        .temps
        .iter()
        .filter_map(|t| t.value.map(|v| (t.key.clone(), v)))
        .collect();

    match machine.apply(&settings, &temps) {
        Ok(actions) => {
            for action in &actions {
                config::log(action);
            }
            to_c(json!({
                "ok": true,
                "actions": actions,
                "error": serde_json::Value::Null,
                "hint": serde_json::Value::Null,
            }))
        }
        Err(e) => {
            set_error(h, &e);
            if let Err(restore_error) = ensure_restored(h) {
                config::log(&format!("restore after apply failure failed: {restore_error}"));
                h.error = Some(format!("{e}; restore automatic failed: {restore_error}"));
            }
            to_c(json!({
                "ok": false,
                "error": &h.error,
                "hint": &h.hint,
                "actions": [],
            }))
        }
    }
}

#[no_mangle]
pub extern "C" fn mf_restore_auto(h: *mut MfHandle) -> *mut c_char {
    if h.is_null() {
        return to_c(json!({"ok": false, "error": "null handle"}));
    }
    let h = unsafe { &mut *h };
    for f in &mut h.settings.fans {
        f.mode = ControlMode::Automatic;
    }
    config::save(&h.settings);
    restore_auto_result(h)
}

/// Put the fans back under firmware control *without* changing the saved
/// profile. Used when the UI is closing, so the next launch can reapply it.
#[no_mangle]
pub extern "C" fn mf_suspend(h: *mut MfHandle) -> *mut c_char {
    if h.is_null() {
        return to_c(json!({"ok": false, "error": "null handle"}));
    }
    let h = unsafe { &mut *h };
    restore_auto_result(h)
}

fn ensure_restored(h: &mut MfHandle) -> crate::smc::Result<()> {
    let result = match h.machine.as_mut() {
        Some(machine) => machine.restore_auto(),
        None => Err(crate::smc::SmcError::msg("SMC unavailable; cannot confirm automatic fan control")),
    };
    h.needs_restore = result.is_err();
    result
}

fn restore_auto_result(h: &mut MfHandle) -> *mut c_char {
    let result = ensure_restored(h);
    match result {
        Ok(()) => {
            config::log("core: fans restored to firmware control");
            to_c(json!({"ok": true}))
        }
        Err(e) => {
            config::log(&format!("automatic fan control restore failed: {e}"));
            set_error(h, &e);
            to_c(json!({"ok": false, "error": &h.error, "hint": &h.hint}))
        }
    }
}
