#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod app;
pub use macndowsfan_core::{config, machine, sensors, smc, win, worker};

use std::sync::mpsc;
use std::sync::Arc;

use eframe::egui;

use crate::machine::Machine;
use crate::smc::{decode_value, key_from_str, Smc};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let probe = args.iter().any(|a| a == "--probe");
    let selftest = args.iter().any(|a| a == "--selftest");
    let stop_mfc = args.iter().any(|a| a == "--stop-mfc");

    if args.iter().any(|a| a == "--elevate") && !win::is_elevated() {
        config::log("--elevate: requesting UAC elevation");
        if win::relaunch_elevated() {
            return;
        }
        config::log("elevation request was cancelled or failed; continuing unelevated");
    }

    // After a reboot the driver service (Manual start) may not be running yet.
    // Starting it needs Administrator, so ask for elevation only when the
    // device is actually missing. A running Macs Fan Control yields access
    // denied instead, which no amount of elevation can fix.
    if !win::is_elevated() && smc_device_missing() {
        config::log("AppleSMC device missing; requesting elevation to start the driver");
        if win::relaunch_elevated() {
            return;
        }
        config::log("elevation cancelled; continuing unelevated");
    }

    if stop_mfc {
        stop_macs_fan_control();
    }

    if probe {
        probe_main();
        return;
    }

    if selftest {
        selftest_main();
        return;
    }

    let settings = config::load();
    let shared = Arc::new(worker::Shared::new(settings));
    let (tx, rx) = mpsc::channel();
    let worker = worker::spawn(shared.clone(), rx);

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([1000.0, 780.0])
            .with_min_inner_size([780.0, 560.0])
            .with_title("macndowsfan"),
        renderer: eframe::Renderer::Glow,
        ..Default::default()
    };

    let result = eframe::run_native(
        "macndowsfan",
        options,
        Box::new(move |cc| Ok(Box::new(app::FanApp::new(cc, shared, tx, worker)))),
    );

    if let Err(e) = result {
        config::log(&format!("eframe failed: {e}"));
    }
}

fn smc_device_missing() -> bool {
    match win::open_device(r"\\.\APPLESMC") {
        Ok(h) => {
            win::close_handle(h);
            false
        }
        Err(win::ERROR_FILE_NOT_FOUND) | Err(win::ERROR_PATH_NOT_FOUND) => true,
        Err(_) => false,
    }
}

fn stop_macs_fan_control() {
    config::log("--stop-mfc: terminating MacsFanControl.exe");
    let _ = std::process::Command::new("taskkill")
        .args(["/F", "/IM", "MacsFanControl.exe"])
        .status();
    std::thread::sleep(std::time::Duration::from_millis(800));
}

fn selftest_main() {
    let mut out = String::new();
    out.push_str("macndowsfan fan control self-test\n");
    match Machine::open() {
        Ok(mut m) => {
            let snap0 = m.sample();
            for f in &snap0.fans {
                out.push_str(&format!(
                    "start: {} actual={:.0} target={:?} min={:.0} max={:.0} forced={}\n",
                    f.name, f.actual, f.target, f.min_rpm, f.max_rpm, f.forced
                ));
            }

            let mut settings = crate::config::Settings::default();
            for f in &snap0.fans {
                let s = settings.fan(f.index);
                s.mode = crate::config::ControlMode::Constant;
                s.rpm = 1500.0;
            }
            let temps = std::collections::HashMap::new();
            match m.apply(&settings, &temps) {
                Ok(actions) => {
                    for a in actions {
                        out.push_str(&format!("apply: {a}\n"));
                    }
                }
                Err(e) => out.push_str(&format!("apply failed: {e}\n")),
            }

            for i in 0..6 {
                std::thread::sleep(std::time::Duration::from_secs(1));
                let s = m.sample();
                for f in &s.fans {
                    out.push_str(&format!(
                        "forced t+{}s: actual={:.0} target={:?} forced={}\n",
                        i + 1,
                        f.actual,
                        f.target,
                        f.forced
                    ));
                }
            }

            m.restore_auto();
            out.push_str("restored automatic\n");
            for i in 0..4 {
                std::thread::sleep(std::time::Duration::from_secs(1));
                let s = m.sample();
                for f in &s.fans {
                    out.push_str(&format!(
                        "auto t+{}s: actual={:.0} target={:?} forced={}\n",
                        i + 1,
                        f.actual,
                        f.target,
                        f.forced
                    ));
                }
            }
        }
        Err(e) => out.push_str(&format!("Machine open failed: {e}\n")),
    }

    let path = config::app_dir().join("selftest.txt");
    let _ = std::fs::create_dir_all(config::app_dir());
    let _ = std::fs::write(&path, &out);
    config::log(&format!("selftest written to {path:?}"));
    println!("{out}");
}

fn probe_main() {
    let mut out = String::new();
    out.push_str("macndowsfan SMC probe\n");
    out.push_str(&format!(
        "elevated: {}\nconfig dir: {:?}\n",
        win::is_elevated(),
        config::app_dir()
    ));
    match win::ensure_service_running("AppleSMC") {
        Ok(()) => out.push_str("service AppleSMC: running\n"),
        Err(e) => out.push_str(&format!("service AppleSMC: start failed ({e})\n")),
    }

    match Smc::open() {
        Ok(smc) => {
            out.push_str("SMC device: opened\n");
            match smc.key_count() {
                Ok(n) => out.push_str(&format!("#KEY: {n}\n")),
                Err(e) => out.push_str(&format!("#KEY: failed: {e}\n")),
            }
            for name in [
                "FNum", "F0ID", "F0Ac", "F0Mn", "F0Mx", "F0Tg", "F0Md", "FS! ",
            ] {
                let Some(k) = key_from_str(name) else { continue };
                match smc.read_auto(&k) {
                    Ok((info, data)) => {
                        let value = decode_value(&info, &data);
                        out.push_str(&format!(
                            "{name}: type={} size={} attrs={} data={:02X?} value={:?}\n",
                            info.type_str(),
                            info.size,
                            info.attrs,
                            data,
                            value
                        ));
                    }
                    Err(e) => out.push_str(&format!("{name}: failed: {e}\n")),
                }
            }
            drop(smc);

            match Machine::open() {
                Ok(mut m) => {
                    out.push_str("\nMachine: opened\n");
                    for line in m.diagnostics() {
                        out.push_str(&format!("  {line}\n"));
                    }
                    let snap = m.sample();
                    out.push_str("\nFans:\n");
                    for f in &snap.fans {
                        out.push_str(&format!(
                            "  #{} {} actual={:.0} target={:?} min={:.0} max={:.0} forced={} controllable={} type={} modekey={}\n",
                            f.index + 1,
                            f.name,
                            f.actual,
                            f.target,
                            f.min_rpm,
                            f.max_rpm,
                            f.forced,
                            f.controllable,
                            f.value_type,
                            f.mode_key
                        ));
                    }
                    out.push_str("\nTemperatures:\n");
                    for t in &snap.temps {
                        out.push_str(&format!(
                            "  {} {:<20} {:?}\n",
                            t.key, t.label, t.value
                        ));
                    }
                    // Leave the machine in the safe state after a diagnostic run.
                    m.restore_auto();
                    out.push_str("\nfan modes restored to automatic\n");
                }
                Err(e) => out.push_str(&format!("\nMachine open failed: {e}\n")),
            }
        }
        Err(e) => {
            out.push_str(&format!("SMC device: OPEN FAILED\n  {e}\n"));
            let hint = e.hint();
            if !hint.is_empty() {
                out.push_str(&format!("  hint: {hint}\n"));
            }
        }
    }

    let path = config::app_dir().join("probe.txt");
    let _ = std::fs::create_dir_all(config::app_dir());
    let _ = std::fs::write(&path, &out);
    config::log(&format!("probe written to {path:?}"));
    println!("{out}");
}
