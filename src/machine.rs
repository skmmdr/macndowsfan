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
    pub ac_info: Option<KeyInfo>,
    pub tg_info: Option<KeyInfo>,
    pub mode_key: Option<([u8; 4], KeyInfo)>,
    pub shared_mode: bool,
    pub min_rpm: f32,
    pub max_rpm: f32,
}

impl FanDesc {
    pub fn controllable(&self) -> bool {
        self.ac_info.is_some()
            && self.tg.is_some()
            && self.tg_info.map_or(false, |info| {
                (info.is_fpe2() && info.size == 2 && self.max_rpm <= u16::MAX as f32 / 4.0)
                    || (info.is_float() && info.size == 4)
            })
            && valid_fan_limits(self.min_rpm, self.max_rpm)
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
    curve_temps: Vec<Option<(String, f32)>>,
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
    if !temp.is_finite() {
        return max_rpm;
    }
    if temp <= start {
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
            // Keep every counted fan even when speed discovery fails: its
            // forced mode still needs to be restored and verified on exit.
            let ac_info = smc.key_info(&ac).ok();
            let mn = key(&format!("F{i}Mn"));
            let mx = key(&format!("F{i}Mx"));
            let tg = key(&format!("F{i}Tg"));
            let id = key(&format!("F{i}ID"));

            let tg_info = smc.key_info(&tg).ok();
            let tg = if tg_info.is_some() { Some(tg) } else { None };

            // A missing per-fan key might be a transient read failure, not
            // evidence that this fan shares F0Md. Never claim restoration
            // until every counted fan's mode can be verified.
            let shared_mode = false;
            let mut mode_key = None;
            if mode_style == ModeStyle::PerFan {
                if let Ok(info) = smc.key_info(&key(&format!("F{i}Md"))) {
                    if info.size == 1 {
                        mode_key = Some((key(&format!("F{i}Md")), info));
                    }
                }
            }

            let name = read_fan_name(&smc, &id).unwrap_or_else(|| format!("Fan {}", i + 1));

            // Zero means unavailable, not an inferred hardware limit.
            let min_rpm = read_number(&smc, &mn).filter(|v| v.is_finite() && *v > 0.0).unwrap_or(0.0);
            let max_rpm = read_number(&smc, &mx).filter(|v| v.is_finite() && *v > 0.0).unwrap_or(0.0);

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
            curve_temps: vec![None; n],
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
                controllable: fan.controllable() && match self.mode_style {
                    ModeStyle::PerFan => fan.mode_key.is_some(),
                    ModeStyle::Bitmask => self.fs_key.is_some(),
                },
                value_type: fan.ac_info.map(|info| info.type_str()).unwrap_or_else(|| "unknown".to_string()),
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

    fn read_forced(&self, fan: &FanDesc) -> Result<bool> {
        match self.mode_style {
            ModeStyle::PerFan => {
                let (k, info) = fan.mode_key.ok_or_else(|| SmcError::msg("fan has no mode key"))?;
                let data = self.smc.read_key(&k, info.size)?;
                data.first().map(|v| *v != 0)
                    .ok_or_else(|| SmcError::msg("fan mode read returned no data"))
            }
            ModeStyle::Bitmask => {
                let (k, info) = self.fs_key.ok_or_else(|| SmcError::msg("fan mode bitmask is unavailable"))?;
                let data = self.smc.read_key(&k, info.size)?;
                if data.len() != info.size as usize {
                    return Err(SmcError::msg("fan mode bitmask read was incomplete"));
                }
                let bits = data.iter().fold(0u32, |bits, byte| (bits << 8) | u32::from(*byte));
                Ok((bits & (1u32 << fan.index)) != 0)
            }
        }
    }

    pub fn is_forced(&self, fan: &FanDesc) -> Option<bool> {
        self.read_forced(fan).ok()
    }

    fn set_forced(&mut self, fan: &FanDesc, forced: bool) -> Result<()> {
        match self.mode_style {
            ModeStyle::PerFan => {
                let (k, _) = fan.mode_key.ok_or_else(|| SmcError::msg("fan has no mode key"))?;
                self.smc.write_key(&k, &[u8::from(forced)])?;
            }
            ModeStyle::Bitmask => {
                let (k, info) = self.fs_key.ok_or_else(|| SmcError::msg("fan mode bitmask is unavailable"))?;
                let mut data = self.smc.read_key(&k, info.size)?;
                if data.len() != info.size as usize {
                    return Err(SmcError::msg("fan mode bitmask read was incomplete"));
                }
                let byte = data.len() - 1 - fan.index / 8;
                let mask = 1u8 << (fan.index % 8);
                if forced { data[byte] |= mask; } else { data[byte] &= !mask; }
                self.smc.write_key(&k, &data)?;
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
        let current_count = detect_fan_count(&self.smc)?;
        if current_count != self.fans.len() {
            return Err(SmcError::msg("SMC fan count changed; cannot verify all fan modes"));
        }
        validate_shared_modes(&self.fans, settings)?;

        for i in 0..self.fans.len() {
            let fan = self.fans[i].clone();
            let s = settings.fan_or_default(fan.index);
            let shares_mode = fan.mode_key.map_or(false, |(key, _)| {
                self.fans.iter().enumerate().any(|(other_index, other)| {
                    other_index != i && other.mode_key.map(|(other_key, _)| other_key) == Some(key)
                })
            });
            if s.mode != ControlMode::Sensor {
                self.curve_temps[i] = None;
            }
            let forced_now = self.read_forced(&fan)?;

            if s.mode == ControlMode::Automatic {
                if forced_now {
                    self.set_forced(&fan, false)?;
                    if self.read_forced(&fan)? {
                        return Err(SmcError::msg(format!("{} remains in forced mode", fan.name)));
                    }
                    self.last_applied[i] = None;
                    actions.push(format!("{}: automatic", fan.name));
                } else {
                    self.last_applied[i] = Some((false, 0.0));
                }
                continue;
            }
            if !fan.controllable() {
                return Err(SmcError::msg(format!(
                    "{} cannot be forced: fan speed, a supported target key, or valid SMC speed limits are unavailable",
                    fan.name
                )));
            }

            let sensor_missing = s.mode == ControlMode::Sensor && !temps.get(&s.sensor).map_or(false, |v| v.is_finite());
            let rpm = match s.mode {
                ControlMode::Constant => clamp_rpm(s.rpm, fan.min_rpm, fan.max_rpm),
                ControlMode::Sensor => {
                    let raw = temps.get(&s.sensor).copied().unwrap_or(f32::NAN);
                    let temp = smooth_curve_temp(&mut self.curve_temps[i], &s.sensor, raw);
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
                match self.read_forced(&fan) {
                    Ok(true) => {}
                    Ok(false) => return Err(SmcError::msg(format!("{} did not enter forced mode", fan.name))),
                    Err(e) => {
                        if let Err(restore_error) = self.set_forced(&fan, false) {
                            return Err(SmcError::msg(format!("{e}; also failed to restore automatic: {restore_error}")));
                        }
                        return Err(e);
                    }
                }
            }
            // Compare against the SMC target, not only our cache. A driver or
            // firmware change can leave forced mode set but alter the target.
            let observed_target = if forced_now {
                let (tg, info) = match (fan.tg, fan.tg_info) {
                    (Some(tg), Some(info)) => (tg, info),
                    _ => return Err(SmcError::msg("fan target key is unavailable")),
                };
                let data = self.smc.read_key(&tg, info.size)?;
                if data.len() != info.size as usize {
                    return Err(SmcError::msg(format!("{} target read was incomplete", fan.name)));
                }
                Some(decode_value(&info, &data)
                    .filter(|v| v.is_finite())
                    .ok_or_else(|| SmcError::msg(format!("{} target read failed", fan.name)))?)
            } else {
                None
            };
            let should_write = shares_mode
                || target_needs_write(self.last_applied[i], forced_now, rpm, observed_target)
                || (sensor_missing && self.last_applied[i].map_or(true, |(_, last)| last < rpm));
            if should_write {
                if let Err(e) = self.write_target(&fan, rpm) {
                    if !forced_now {
                        if let Err(restore_error) = self.set_forced(&fan, false) {
                            return Err(SmcError::msg(format!("{e}; also failed to restore automatic: {restore_error}")));
                        }
                    }
                    return Err(e);
                }
                self.last_applied[i] = Some((true, rpm));
                actions.push(format!("{}: {:.0} RPM", fan.name, rpm));
            }
        }

        Ok(actions)
    }

    pub fn restore_auto(&mut self) -> Result<()> {
        // Still attempt all known fans if the count cannot be verified, but
        // never report successful restoration while other fans may be missing.
        let mut first_error = match detect_fan_count(&self.smc) {
            Ok(count) if count == self.fans.len() => None,
            Ok(_) => Some(SmcError::msg("SMC fan count changed; cannot verify all fan modes")),
            Err(e) => Some(e),
        };
        for i in 0..self.fans.len() {
            let fan = self.fans[i].clone();
            // Attempt every fan even if an earlier one failed. Never infer
            // automatic mode from an unreadable mode key.
            let result = self.set_forced(&fan, false).and_then(|()| {
                if self.read_forced(&fan)? {
                    Err(SmcError::msg(format!("{} remains in forced mode", fan.name)))
                } else {
                    Ok(())
                }
            });
            if let Err(e) = result {
                if first_error.is_none() { first_error = Some(e); }
            }
            self.last_applied[i] = None;
        }
        self.curve_temps.fill(None);
        match first_error { Some(e) => Err(e), None => Ok(()) }
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
                f.ac_info.map(|info| info.type_str()).unwrap_or_else(|| "unknown".to_string()),
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

/// Fans sharing a mode key cannot independently use automatic and forced modes.
fn validate_shared_modes(fans: &[FanDesc], settings: &Settings) -> Result<()> {
    for (i, fan) in fans.iter().enumerate() {
        let Some((key, _)) = fan.mode_key else { continue };
        let forced = settings.fan_or_default(fan.index).mode != ControlMode::Automatic
            && fan.controllable();
        for other in &fans[..i] {
            if other.mode_key.map(|(other_key, _)| other_key) == Some(key) {
                let other_forced = settings.fan_or_default(other.index).mode != ControlMode::Automatic
                    && other.controllable();
                if forced != other_forced {
                    return Err(SmcError::msg(format!(
                        "{} and {} share a mode key and must both be automatic or both forced",
                        fan.name, other.name
                    )));
                }
            }
        }
    }
    Ok(())
}

/// Smooth each fan's control sensor independently.
fn smooth_curve_temp(previous: &mut Option<(String, f32)>, key: &str, raw: f32) -> f32 {
    if !raw.is_finite() {
        *previous = None;
        return raw;
    }
    let smoothed = match previous.as_ref() {
        Some((previous_key, value)) if previous_key == key => *value * 0.7 + raw * 0.3,
        _ => raw,
    };
    *previous = Some((key.to_string(), smoothed));
    smoothed
}

fn valid_fan_limits(min: f32, max: f32) -> bool {
    min.is_finite() && max.is_finite() && min > 0.0 && max > min
}

fn target_needs_write(last: Option<(bool, f32)>, forced_now: bool, rpm: f32, observed: Option<f32>) -> bool {
    !forced_now || match last {
        Some((was_forced, last_rpm)) => {
            !was_forced || (last_rpm - rpm).abs() > 30.0
                || observed.map_or(true, |current| !current.is_finite() || (current - last_rpm).abs() > 1.0)
        }
        None => true,
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

fn parse_fan_count(data: &[u8]) -> Result<usize> {
    let n = match data {
        [n] => *n as usize,
        [hi, lo] => u16::from_be_bytes([*hi, *lo]) as usize,
        [a, b, c, d] => u32::from_be_bytes([*a, *b, *c, *d]) as usize,
        _ => return Err(SmcError::msg("invalid FNum length; cannot verify all fan modes")),
    };
    if (1..=10).contains(&n) {
        Ok(n)
    } else {
        Err(SmcError::msg("invalid FNum value; cannot verify all fan modes"))
    }
}

fn detect_fan_count(smc: &Smc) -> Result<usize> {
    let (info, data) = smc.read_auto(&key("FNum"))
        .map_err(|e| SmcError::msg(format!("cannot read FNum; cannot verify all fan modes: {e}")))?;
    if data.len() != info.size as usize {
        return Err(SmcError::msg("incomplete FNum read; cannot verify all fan modes"));
    }
    parse_fan_count(&data)
}

#[cfg(test)]
mod tests {
    use super::{parse_fan_count, sensor_curve, smooth_curve_temp, target_needs_write, valid_fan_limits, validate_shared_modes, FanDesc};
    use crate::config::{ControlMode, Settings};
    use crate::smc::KeyInfo;

    #[test]
    fn unavailable_sensor_uses_maximum_speed() {
        assert_eq!(sensor_curve(f32::NAN, 55.0, 85.0, 1200.0, 2640.0), 2640.0);
        assert_eq!(sensor_curve(f32::INFINITY, 55.0, 85.0, 1200.0, 2640.0), 2640.0);
        assert_eq!(sensor_curve(50.0, 55.0, 85.0, 1200.0, 2640.0), 1200.0);
        assert_eq!(sensor_curve(85.0, 55.0, 85.0, 1200.0, 2640.0), 2640.0);
    }

    #[test]
    fn sensor_smoothing_is_independent_per_fan_and_resets() {
        let mut first = None;
        let mut second = None;
        assert_eq!(smooth_curve_temp(&mut first, "TC0P", 50.0), 50.0);
        assert_eq!(smooth_curve_temp(&mut second, "TG0d", 80.0), 80.0);
        assert!((smooth_curve_temp(&mut first, "TC0P", 60.0) - 53.0).abs() < 0.001);
        assert!((smooth_curve_temp(&mut second, "TG0d", 90.0) - 83.0).abs() < 0.001);
        assert!(smooth_curve_temp(&mut first, "TC0P", f32::NAN).is_nan());
        assert_eq!(smooth_curve_temp(&mut first, "TC0P", 70.0), 70.0);
    }

    #[test]
    fn shared_mode_rejects_mixed_automatic_and_forced() {
        let info = KeyInfo { size: 1, ty: *b"ui8 ", attrs: 0 };
        let target_info = KeyInfo { size: 2, ty: *b"fpe2", attrs: 0 };
        let fan = |index| FanDesc {
            index,
            name: format!("Fan {index}"),
            ac: *b"F0Ac", mn: *b"F0Mn", mx: *b"F0Mx",
            tg: Some(*b"F0Tg"), ac_info: Some(info), tg_info: Some(target_info),
            mode_key: Some((*b"F0Md", info)), shared_mode: index != 0,
            min_rpm: 1200.0, max_rpm: 2640.0,
        };
        let fans = [fan(0), fan(1)];
        let mut settings = Settings::default();
        settings.fan(0).mode = ControlMode::Constant;
        assert!(validate_shared_modes(&fans, &settings).is_err());
        settings.fan(1).mode = ControlMode::Sensor;
        assert!(validate_shared_modes(&fans, &settings).is_ok());
        settings.fan(0).mode = ControlMode::Automatic;
        settings.fan(1).mode = ControlMode::Automatic;
        assert!(validate_shared_modes(&fans, &settings).is_ok());
        let mut missing_speed = fan(0);
        missing_speed.ac_info = None;
        assert!(!missing_speed.controllable());
        let mut missing_limits = fan(0);
        missing_limits.max_rpm = 0.0;
        assert!(!missing_limits.controllable());
        let mut unsupported_target = fan(0);
        unsupported_target.tg_info = Some(info);
        assert!(!unsupported_target.controllable());
        let mut unrepresentable_target = fan(0);
        unrepresentable_target.max_rpm = 17000.0;
        assert!(!unrepresentable_target.controllable());
        assert!(fan(0).controllable());
    }

    #[test]
    fn requires_known_fan_count_and_reported_limits() {
        assert!(matches!(parse_fan_count(&[2]), Ok(2)));
        assert!(matches!(parse_fan_count(&[0, 2]), Ok(2)));
        assert!(matches!(parse_fan_count(&[0, 0, 0, 2]), Ok(2)));
        for invalid in [&[][..], &[0][..], &[11][..], &[0, 0, 1, 0][..], &[1, 2, 3][..]] {
            assert!(parse_fan_count(invalid).is_err());
        }
        assert!(valid_fan_limits(1200.0, 2640.0));
        assert!(!valid_fan_limits(0.0, 2640.0));
        assert!(!valid_fan_limits(1200.0, 0.0));
        assert!(!valid_fan_limits(1200.0, 1200.0));
        assert!(!valid_fan_limits(f32::NAN, 2640.0));
    }

    #[test]
    fn deadband_is_relative_to_last_written_target() {
        let last_written = Some((true, 1200.0));
        assert!(!target_needs_write(last_written, true, 1215.0, Some(1200.0)));
        assert!(!target_needs_write(last_written, true, 1230.0, Some(1200.0)));
        assert!(target_needs_write(last_written, true, 1231.0, Some(1200.0)));
        assert!(target_needs_write(last_written, false, 1200.0, None));
        assert!(target_needs_write(last_written, true, 1200.0, Some(1400.0)));
        assert!(target_needs_write(last_written, true, 1200.0, None));
        assert!(target_needs_write(last_written, true, 1200.0, Some(f32::NAN)));
        assert!(!target_needs_write(last_written, true, 1200.0, Some(1200.25)));
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
