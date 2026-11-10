use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ControlMode {
    Automatic,
    Constant,
    Sensor,
}

impl Default for ControlMode {
    fn default() -> Self {
        Self::Automatic
    }
}

impl ControlMode {
    pub fn label(self) -> &'static str {
        match self {
            Self::Automatic => "Automatic",
            Self::Constant => "Constant speed",
            Self::Sensor => "Sensor-based",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct FanSetting {
    #[serde(default = "default_profile")]
    pub profile: String,
    #[serde(default)]
    pub mode: ControlMode,
    #[serde(default = "default_rpm")]
    pub rpm: f32,
    #[serde(default = "default_sensor")]
    pub sensor: String,
    #[serde(default = "default_start_temp")]
    pub start_temp: f32,
    #[serde(default = "default_max_temp")]
    pub max_temp: f32,
}

fn default_profile() -> String {
    "custom".to_string()
}

fn default_rpm() -> f32 {
    1500.0
}
fn default_sensor() -> String {
    "TC0P".to_string()
}
fn default_start_temp() -> f32 {
    55.0
}
fn default_max_temp() -> f32 {
    85.0
}

impl Default for FanSetting {
    fn default() -> Self {
        Self {
            profile: default_profile(),
            mode: ControlMode::Automatic,
            rpm: default_rpm(),
            sensor: default_sensor(),
            start_temp: default_start_temp(),
            max_temp: default_max_temp(),
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Settings {
    #[serde(default)]
    pub fans: Vec<FanSetting>,
}

impl Settings {
    pub fn fan(&mut self, index: usize) -> &mut FanSetting {
        while self.fans.len() <= index {
            self.fans.push(FanSetting::default());
        }
        &mut self.fans[index]
    }

    pub fn fan_or_default(&self, index: usize) -> FanSetting {
        self.fans.get(index).cloned().unwrap_or_default()
    }
}

pub fn app_dir() -> PathBuf {
    let base = std::env::var_os("APPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    base.join("MacndowsFan")
}

pub fn config_path() -> PathBuf {
    app_dir().join("settings.json")
}

pub fn log_path() -> PathBuf {
    app_dir().join("macndowsfan.log")
}

pub fn load() -> Settings {
    let path = config_path();
    match fs::read_to_string(&path) {
        Ok(text) => {
            // Tolerate a UTF-8 BOM (Notepad/PowerShell like to add one).
            let text = text.trim_start_matches('\u{feff}');
            serde_json::from_str(text).unwrap_or_else(|e| {
                log(&format!("settings parse error ({e}); using defaults"));
                Settings::default()
            })
        }
        Err(_) => Settings::default(),
    }
}

pub fn save(settings: &Settings) {
    let dir = app_dir();
    if let Err(e) = fs::create_dir_all(&dir) {
        log(&format!("cannot create {dir:?}: {e}"));
        return;
    }
    match serde_json::to_string_pretty(settings) {
        Ok(text) => {
            if let Err(e) = fs::write(config_path(), text) {
                log(&format!("cannot write settings: {e}"));
            }
        }
        Err(e) => log(&format!("cannot serialize settings: {e}")),
    }
}

pub fn log(msg: &str) {
    use std::io::Write;
    let dir = app_dir();
    let _ = fs::create_dir_all(&dir);
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    if let Ok(mut f) = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_path())
    {
        let _ = writeln!(f, "[{stamp}] {msg}");
    }
}
