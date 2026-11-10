//! Fan discovery and control logic on top of the SMC transport.

use std::collections::HashMap;

use crate::config::{ControlMode, Settings};
use crate::sensors::{self, SensorDesc};
use crate::smc::{
    decode_value, encode_rpm, key_from_str, key_to_string, KeyInfo, Result, Smc, SmcError,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ModeStyle {
    PerFan,
    Bitmask,
}

impl ModeStyle {
    pub fn label(self) -> &'static str {
        match self {
            Self::PerFan => "per-fan mode key (F0Md)",
            Self::Bitmask => "global bitmask (FS!)",
        }
    }
}

#[derive(Clone)]
pub struct FanDesc {
    pub index: usize,
    pub name: String,
    pub ac: [u8; 4],
    pub mn: [u8; 4],
    pub mx: [u8; 4],
    pub tg: Option<[u8; 4]>,
    pub ac_info: KeyInfo,
    pub tg_info: Option<KeyInfo>,
    pub mode_key: Option<([u8; 4], KeyInfo)>,
    pub shared_mode: bool,
    pub min_rpm: f32,
    pub max_rpm: f32,
}

impl FanDesc {
    pub fn controllable(&self) -> bool {
        self.tg.is_some() && self.tg_info.is_some()
    }
}

#[derive(Clone, Default)]
pub struct FanReading {
    pub index: usize,
    pub name: String,
    pub actual: f32,
    pub target: Option<f32>,
    pub min_rpm: f32,
    pub max_rpm: f32,
    pub forced: bool,
    pub controllable: bool,
    pub value_type: String,
    pub mode_key: String,
}

#[derive(Clone, Default)]
pub struct TempReading {
    pub key: String,
    pub label: String,
    pub value: Option<f32>,
}

#[derive(Clone, Default)]
pub struct Snapshot {
    pub fans: Vec<FanReading>,
    pub temps: Vec<TempReading>,
    pub error: Option<String>,
    pub error_hint: Option<String>,
    pub key_count: Option<u32>,
    pub mode_style: String,
    pub updated_ms: u64,
}

pub struct Machine {
    pub smc: Smc,
    pub fans: Vec<FanDesc>,
    pub sensors: Vec<SensorDesc>,
    pub mode_style: ModeStyle,
    pub fs_key: Option<([u8; 4], KeyInfo)>,
    pub key_count: Option<u32>,
    last_applied: Vec<Option<(bool, f32)>>,
    curve_temp: Option<(String, f32)>,
}

fn key(s: &str) -> [u8; 4] {
    key_from_str(s).expect("SMC keys are 4 characters")
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn read_number(smc: &Smc, k: &[u8; 4]) -> Option<f32> {
    let (info, data) = smc.read_auto(k).ok()?;
    decode_value(&info, &data)
}

pub fn sensor_curve(temp: f32, start: f32, max: f32, min_rpm: f32, max_rpm: f32) -> f32 {
    let (min_rpm, max_rpm) = (min_rpm.min(max_rpm), min_rpm.max(max_rpm));
    if !temp.is_finite() || temp <= start {
        return min_rpm;
    }
    if temp >= max || (max - start) <= 0.1 {
        return max_rpm;
    }
    let t = (temp - start) / (max - start);
    min_rpm + (max_rpm - min_rpm) * t.clamp(0.0, 1.0)
}

impl Machine {
    pub fn open() -> Result<Self> {
        let smc = Smc::open()?;

        let key_count = smc.key_count().ok();
        let fan_count = detect_fan_count(&smc)?;

        // Which mechanism does this Mac use to force fan speeds?
        let f0md_info = smc.key_info(&key("F0Md")).ok().filter(|i| i.size == 1);
        let fs_info = smc
            .key_info(&key("FS! "))
            .ok()
            .filter(|i| i.size == 2 || i.size == 4);
        let mode_style = if f0md_info.is_some() {
            ModeStyle::PerFan
        } else if fs_info.is_some() {
            ModeStyle::Bitmask
        } else {
            ModeStyle::PerFan
        };

        let mut fans = Vec::new();
        for i in 0..fan_count {
            let ac = key(&format!("F{i}Ac"));
            let ac_info = match smc.key_info(&ac) {
                Ok(info) => info,
                Err(_) => continue,
            };
            let mn = key(&format!("F{i}Mn"));
            let mx = key(&format!("F{i}Mx"));
            let tg = key(&format!("F{i}Tg"));
            let id = key(&format!("F{i}ID"));

            let tg_info = smc.key_info(&tg).ok();
            let tg = if tg_info.is_some() { Some(tg) } else { None };

            // Per-fan mode key, falling back to the first fan's key on models
            // where a single mode key drives synchronized fans.
            let mut shared_mode = false;
            let mut mode_key = None;
            if mode_style == ModeStyle::PerFan {
                if let Ok(info) = smc.key_info(&key(&format!("F{i}Md"))) {
                    if info.size == 1 {
                        mode_key = Some((key(&format!("F{i}Md")), info));
                    }
                }
                if mode_key.is_none() {
                    if let Some(info) = f0md_info.clone() {
                        mode_key = Some((key("F0Md"), info));
                        shared_mode = true;
                    }
                }
            }

            let name = read_fan_name(&smc, &id).unwrap_or_else(|| format!("Fan {}", i + 1));

            let min_rpm = read_number(&smc, &mn).unwrap_or(0.0).max(0.0);
            let mut max_rpm = read_number(&smc, &mx).unwrap_or(0.0).max(0.0);
            if max_rpm <= min_rpm {
                max_rpm = (min_rpm + 2000.0).max(3000.0);
            }

            fans.push(FanDesc {
                index: i,
                name,
                ac,
                mn,
                mx,
                tg,
                ac_info,
                tg_info,
                mode_key,
                shared_mode,
                min_rpm,
                max_rpm,
            });
        }

        if fans.is_empty() {
            return Err(SmcError::msg(
                "no fans detected through SMC (unexpected on iMac14,2)",
            ));
        }

        let sensors = sensors::detect(&smc);
        let n = fans.len();

        Ok(Self {
            smc,
            fans,
            sensors,
            mode_style,
            fs_key: fs_info.map(|info| (key("FS! "), info)),
            key_count,
            last_applied: vec![None; n],
            curve_temp: None,
        })
    }

    /// Re-probe sensors that were not populated when the machine was opened
    /// (some die sensors read invalid values right after boot).
    pub fn refresh_sensors(&mut self) {
        let found = sensors::detect(&self.smc);
        for s in found {
            if !self.sensors.iter().any(|e| e.key == s.key) {
                self.sensors.push(s);
            }
        }
    }

    pub fn sample(&self) -> Snapshot {
        let mut snap = Snapshot {
            mode_style: self.mode_style.label().to_string(),
            key_count: self.key_count,
            updated_ms: now_ms(),
            ..Default::default()
        };

        for fan in &self.fans {
            let actual = read_number(&self.smc, &fan.ac).unwrap_or(f32::NAN);
            let target = fan.tg.and_then(|k| read_number(&self.smc, &k));
            snap.fans.push(FanReading {
                index: fan.index,
                name: fan.name.clone(),
                actual,
                target,
                min_rpm: fan.min_rpm,
                max_rpm: fan.max_rpm,
                forced: self.is_forced(fan).unwrap_or(false),
                controllable: fan.controllable(),
                value_type: fan.ac_info.type_str(),
                mode_key: fan
                    .mode_key
                    .map(|(k, _)| key_to_string(&k))
                    .unwrap_or_else(|| "FS! ".to_string()),
            });
        }

        for s in &self.sensors {
            let value = self
                .smc
                .read_key(&s.key, s.info.size)
                .ok()
                .and_then(|data| decode_value(&s.info, &data))
                .filter(|v| v.is_finite() && (0.0..=110.0).contains(v));
            snap.temps.push(TempReading {
                key: s.key_str.clone(),
                label: s.label.clone(),
                value,
            });
        }

        snap
    }

    fn mode_value(&self, fan: &FanDesc) -> Option<u8> {
        match self.mode_style {
            ModeStyle::PerFan => {
                let (k, info) = fan.mode_key?;
                let data = self.smc.read_key(&k, info.size).ok()?;
                data.first().copied()
            }
            ModeStyle::Bitmask => {
                let (k, info) = self.fs_key?;
                let data = self.smc.read_key(&k, info.size).ok()?;
                let bits = if data.len() >= 2 {
                    u16::from_be_bytes([data[0], data[1]])
                } else {
                    data.first().copied().unwrap_or(0) as u16
                };
                Some(((bits >> fan.index) & 1) as u8)
            }
        }
    }

    pub fn is_forced(&self, fan: &FanDesc) -> Option<bool> {
        self.mode_value(fan).map(|v| v != 0)
    }

    fn set_forced(&mut self, fan: &FanDesc, forced: bool) -> Result<()> {
        match self.mode_style {
            ModeStyle::PerFan => {
                if let Some((k, _info)) = fan.mode_key {
                    self.smc.write_key(&k, &[u8::from(forced)])?;
                }
            }
            ModeStyle::Bitmask => {
                if let Some((k, info)) = self.fs_key {
                    let data = self.smc.read_key(&k, info.size).unwrap_or_default();
                    let mut bits = if data.len() >= 2 {
                        u16::from_be_bytes([data[0], data[1]])
                    } else {
                        0
                    };
                    if forced {
                        bits |= 1 << fan.index;
                    } else {
                        bits &= !(1 << fan.index);
                    }
                    let bytes = if info.size >= 2 || data.len() >= 2 {
                        bits.to_be_bytes().to_vec()
                    } else {
                        vec![bits as u8]
                    };
                    self.smc.write_key(&k, &bytes)?;
                }
            }
        }
        Ok(())
    }

    fn write_target(&mut self, fan: &FanDesc, rpm: f32) -> Result<()> {
        let (Some(tg), Some(info)) = (fan.tg, fan.tg_info.as_ref()) else {
            return Err(SmcError::msg("fan has no target key"));
        };
        let rpm = clamp_rpm(rpm, fan.min_rpm, fan.max_rpm);
        let bytes = encode_rpm(info, rpm);
        self.smc.write_key(&tg, &bytes)
    }

    /// Apply the user's profile. Returns human-readable actions for the log.
    pub fn apply(
        &mut self,
        settings: &Settings,
        temps: &HashMap<String, f32>,
    ) -> Result<Vec<String>> {
        let mut actions = Vec::new();

        for i in 0..self.fans.len() {
            let fan = self.fans[i].clone();
            let s = settings.fan_or_default(fan.index);
            if s.mode != ControlMode::Sensor {
                self.curve_temp = None;
            }
            let forced_now = self.is_forced(&fan).unwrap_or(false);

            if s.mode == ControlMode::Automatic || !fan.controllable() {
                if forced_now {
                    self.set_forced(&fan, false)?;
                    self.last_applied[fan.index] = None;
                    actions.push(format!("{}: automatic", fan.name));
                } else {
                    self.last_applied[fan.index] = Some((false, 0.0));
                }
                continue;
            }

            let rpm = match s.mode {
                ControlMode::Constant => clamp_rpm(s.rpm, fan.min_rpm, fan.max_rpm),
                ControlMode::Sensor => {
                    let raw = temps.get(&s.sensor).copied().unwrap_or(f32::NAN);
                    let temp = self.smooth_curve_temp(&s.sensor, raw);
                    sensor_curve(
                        temp,
                        s.start_temp,
                        s.max_temp,
                        safe_min_rpm(fan.min_rpm),
                        fan.max_rpm,
                    )
                }
                ControlMode::Automatic => unreachable!(),
            };

            if !forced_now {
                self.set_forced(&fan, true)?;
            }

            let should_write = match self.last_applied[fan.index] {
                Some((was_forced, last_rpm)) => !was_forced || (last_rpm - rpm).abs() > 30.0,
                None => true,
            };
            if should_write {
                self.write_target(&fan, rpm)?;
                actions.push(format!("{}: {:.0} RPM", fan.name, rpm));
            }
            self.last_applied[fan.index] = Some((true, rpm));
        }

        Ok(actions)
    }

    /// Smooth the control sensor so fan target does not chase SMC noise.
    fn smooth_curve_temp(&mut self, key: &str, raw: f32) -> f32 {
        if !raw.is_finite() {
            return raw;
        }
        if let Some((previous_key, previous)) = self.curve_temp.take() {
            if previous_key == key {
                let smoothed = previous * 0.7 + raw * 0.3;
                self.curve_temp = Some((previous_key, smoothed));
                return smoothed;
            }
        }
        self.curve_temp = Some((key.to_string(), raw));
        raw
    }

    pub fn restore_auto(&mut self) {
        for i in 0..self.fans.len() {
            let fan = self.fans[i].clone();
            if self.is_forced(&fan).unwrap_or(false) {
                let _ = self.set_forced(&fan, false);
            }
        }
        for slot in &mut self.last_applied {
            *slot = None;
        }
        self.curve_temp = None;
    }

    pub fn diagnostics(&self) -> Vec<String> {
        let mut lines = Vec::new();
        lines.push(format!("Mode style: {}", self.mode_style.label()));
        if let Some(c) = self.key_count {
            lines.push(format!("SMC key count: {c}"));
        }
        for f in &self.fans {
            lines.push(format!(
                "{} [{}] keys {}/{}/{}/{}{} type {} range {:.0}-{:.0} RPM mode-key {}{}",
                f.index + 1,
                f.name,
                key_to_string(&f.ac),
                key_to_string(&f.mn),
                key_to_string(&f.mx),
                f.tg.map(|k| key_to_string(&k)).unwrap_or("-".into()),
                f.tg_info
                    .as_ref()
                    .map(|i| format!(" ({})", i.type_str()))
                    .unwrap_or_default(),
                f.ac_info.type_str(),
                f.min_rpm,
                f.max_rpm,
                f.mode_key
                    .as_ref()
                    .map(|(k, _)| key_to_string(k))
                    .unwrap_or_else(|| "FS! ".into()),
                if f.shared_mode { " (shared)" } else { "" }
            ));
        }
        for s in &self.sensors {
            lines.push(format!(
                "{} {} type {} size {}",
                s.key_str,
                s.label,
                s.info.type_str(),
                s.info.size
            ));
        }
        lines
    }
}

fn clamp_rpm(rpm: f32, min: f32, max: f32) -> f32 {
    if !rpm.is_finite() {
        return safe_min_rpm(min);
    }
    let lo = safe_min_rpm(min);
    let hi = if max > lo { max } else { lo };
    rpm.clamp(lo, hi)
}

/// A reported minimum of 0 usually means "unknown"; never let a fan be
/// commanded below a safe floor.
pub fn safe_min_rpm(min: f32) -> f32 {
    if min.is_finite() && min > 0.0 {
        min
    } else {
        800.0
    }
}

fn detect_fan_count(smc: &Smc) -> Result<usize> {
    if let Ok((_info, data)) = smc.read_auto(&key("FNum")) {
        if !data.is_empty() {
            let n = match data.len() {
                1 => data[0] as usize,
                n if n >= 4 => u32::from_be_bytes([data[0], data[1], data[2], data[3]]) as usize,
                _ => data[data.len() - 1] as usize,
            };
            if (1..=10).contains(&n) {
                return Ok(n);
            }
        }
    }

    // Fallback: probe F0..F9 actual-speed keys.
    let mut count = 0;
    for i in 0..10 {
        if smc.key_info(&key(&format!("F{i}Ac"))).is_ok() {
            count = i + 1;
        } else if i > 0 {
            break;
        }
    }
    if count == 0 {
        Err(SmcError::msg("unable to determine fan count (FNum/F0Ac missing)"))
    } else {
        Ok(count)
    }
}

fn read_fan_name(smc: &Smc, id: &[u8; 4]) -> Option<String> {
    let (info, data) = smc.read_auto(id).ok()?;
    if data.is_empty() {
        return None;
    }
    // F0ID is either a plain string or a small binary header followed by the
    // name (iMac14,2 returns 00 00 10 00 "Main " ...). Take the longest
    // printable run.
    let mut best = String::new();
    let mut current = String::new();
    for b in data.iter() {
        if b.is_ascii_graphic() || *b == b' ' {
            current.push(*b as char);
        } else {
            if current.len() > best.len() {
                best = std::mem::take(&mut current);
            }
            current.clear();
        }
    }
    if current.len() > best.len() {
        best = current;
    }
    let name = best.trim().to_string();
    if name.is_empty() || info.ty == [0, 0, 0, 0] {
        None
    } else {
        Some(name)
    }
}
