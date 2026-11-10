//! Temperature sensors. The iMac SMC exposes a stable set of temperature keys;
//! we probe a curated list and keep the ones that exist on this machine.

use crate::smc::{key_from_str, KeyInfo, Smc};

/// Keys verified against a full 632-key SMC scan on iMac14,2. Key case is
/// significant: the CPU cores are `TC0c`..`TC3c` (lowercase c), while
/// `TC0E`/`TC0F`/`TH0P` exist but are unpopulated on this model.
const KNOWN: &[(&str, &str)] = &[
    ("TA0P", "Room air"),
    ("TC0P", "CPU area"),
    ("TC0c", "CPU core 1"),
    ("TC1c", "CPU core 2"),
    ("TC2c", "CPU core 3"),
    ("TC3c", "CPU core 4"),
    ("TCXc", "CPU package"),
    ("TCGc", "CPU graphics"),
    ("TCSc", "CPU uncore"),
    ("TG0P", "GPU area"),
    ("TG0d", "GPU core"),
    ("TG0D", "GPU secondary 1"),
    ("TG0E", "GPU secondary 2"),
    ("TG0F", "GPU secondary 3"),
    ("TM0P", "RAM slot 1"),
    ("TM1P", "RAM slot 2"),
    ("TM2P", "RAM slot 3"),
    ("TM3P", "RAM slot 4"),
    ("Tp2H", "Power supply"),
    ("TH1A", "Drive bay 1"),
    ("TH1B", "Drive bay 2"),
    ("TL0P", "Screen panel"),
    ("Tb0P", "Thunderbolt"),
];

#[derive(Clone)]
pub struct SensorDesc {
    pub key: [u8; 4],
    pub key_str: String,
    pub label: String,
    pub info: KeyInfo,
}

pub fn detect(smc: &Smc) -> Vec<SensorDesc> {
    let mut out: Vec<SensorDesc> = Vec::new();
    for (key_str, label) in KNOWN {
        let Some(key) = key_from_str(key_str) else {
            continue;
        };
        let Ok(info) = smc.key_info(&key) else {
            continue;
        };
        if !info.is_temp() {
            continue;
        }
        // Drop keys that exist but are not populated on this model (some return
        // negative or absurd values, e.g. unused die sensors on iMac14,2).
        let value = smc
            .read_key(&key, info.size)
            .ok()
            .and_then(|data| crate::smc::decode_value(&info, &data));
        let Some(v) = value else { continue };
        if !(v.is_finite() && (0.0..=110.0).contains(&v)) {
            continue;
        }
        if out.iter().any(|s| s.key == key) {
            continue;
        }
        out.push(SensorDesc {
            key,
            key_str: (*key_str).to_string(),
            label: (*label).to_string(),
            info,
        });
    }
    out
}

