//! Apple SMC transport over the signed `applesmc.sys` driver that Macs Fan
//! Control installs (`\\.\APPLESMC`).
//!
//! The IOCTL protocol was recovered from the driver + Macs Fan Control:
//!   0x00220000 read  : in  { u32 key, u8 size }              -> 32 bytes
//!   0x00220004 write : in  { u32 key, u8 size, u8 data[] }   -> 1 byte
//!   0x00220008 index : in  { u32 index }                      -> 4 key chars
//!   0x0022000C info  : in  { u32 key }                        -> {u8 size, u8 type[4], u8 attrs}
//!   0x00220020 init  : in  {}                                 -> 1 byte

use std::fmt;

use crate::win;

pub const IOCTL_READ_KEY: u32 = 0x0022_0000;
pub const IOCTL_WRITE_KEY: u32 = 0x0022_0004;
#[allow(dead_code)]
pub const IOCTL_GET_KEY_BY_INDEX: u32 = 0x0022_0008;
pub const IOCTL_GET_KEY_INFO: u32 = 0x0022_000C;
pub const IOCTL_INIT: u32 = 0x0022_0020;

const DEVICE_PATH: &str = r"\\.\APPLESMC";

#[derive(Debug, Clone)]
pub struct SmcError {
    pub code: Option<u32>,
    pub context: String,
}

impl SmcError {
    pub fn msg(context: impl Into<String>) -> Self {
        Self {
            code: None,
            context: context.into(),
        }
    }

    pub fn win(context: impl Into<String>, code: u32) -> Self {
        Self {
            code: Some(code),
            context: context.into(),
        }
    }

    pub fn hint(&self) -> &'static str {
        self.code.map(win::error_hint).unwrap_or("")
    }
}

impl fmt::Display for SmcError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.code {
            Some(c) => write!(f, "{} (Windows error {})", self.context, c),
            None => write!(f, "{}", self.context),
        }
    }
}

pub type Result<T> = std::result::Result<T, SmcError>;

#[derive(Debug, Clone, Copy)]
pub struct KeyInfo {
    pub size: u8,
    pub ty: [u8; 4],
    pub attrs: u8,
}

impl KeyInfo {
    pub fn type_str(&self) -> String {
        let s: String = self
            .ty
            .iter()
            .map(|b| {
                if b.is_ascii_graphic() || *b == b' ' {
                    *b as char
                } else {
                    '.'
                }
            })
            .collect();
        s
    }

    pub fn is_fpe2(&self) -> bool {
        &self.ty == b"fpe2"
    }

    pub fn is_float(&self) -> bool {
        &self.ty == b"flt "
    }

    pub fn is_temp(&self) -> bool {
        matches!(&self.ty, b"sp78" | b"flt " | b"fpe2" | b"sp87" | b"si16")
    }
}

/// Pack a 4-character SMC key into a big-endian integer representation
/// (useful for diagnostics; the driver wants the raw 4 characters instead).
#[allow(dead_code)]
pub fn key_u32(key: &[u8; 4]) -> u32 {
    u32::from_be_bytes(*key)
}

pub fn key_from_str(s: &str) -> Option<[u8; 4]> {
    let b = s.as_bytes();
    if b.len() == 4 {
        Some([b[0], b[1], b[2], b[3]])
    } else {
        None
    }
}

pub fn key_to_string(key: &[u8; 4]) -> String {
    key.iter().map(|b| *b as char).collect()
}

fn looks_like_type(bytes: &[u8]) -> bool {
    const KNOWN: [&[u8; 4]; 12] = [
        b"fpe2", b"flt ", b"sp78", b"sp87", b"si16", b"ui8 ", b"ui16", b"ui32", b"ch8*",
        b"flag", b"hex_", b"fp88",
    ];
    if KNOWN.iter().any(|k| *k == bytes) {
        return true;
    }
    bytes
        .iter()
        .all(|b| b.is_ascii_graphic() || *b == b' ')
}

pub struct Smc {
    handle: win::HANDLE,
}

impl Smc {
    pub fn open() -> Result<Self> {
        // The driver is a kernel service installed by Macs Fan Control. Starting
        // it requires Administrator; if it is already running this is a no-op.
        let service_result = win::ensure_service_running("AppleSMC");
        if let Err(code) = service_result {
            // Continue anyway: maybe the device exists but the service name differs.
            if code != win::ERROR_ACCESS_DENIED {
                std::thread::sleep(std::time::Duration::from_millis(150));
            }
        }

        let handle = win::open_device(DEVICE_PATH)
            .map_err(|e| SmcError::win(format!("opening {DEVICE_PATH}"), e))?;
        let smc = Self { handle };
        // Best-effort wake/init; ignore failures on drivers that do not implement it.
        let _ = smc.init();
        Ok(smc)
    }

    fn ioctl(&self, code: u32, input: &[u8], output: &mut [u8]) -> Result<u32> {
        win::device_io_control(self.handle, code, input, output).map_err(|e| {
            SmcError::win(
                format!("DeviceIoControl(0x{code:08X}) on {DEVICE_PATH}"),
                e,
            )
        })
    }

    pub fn init(&self) -> Result<()> {
        let mut out = [0u8; 1];
        self.ioctl(IOCTL_INIT, &[], &mut out)?;
        Ok(())
    }

    pub fn read_key(&self, key: &[u8; 4], size: u8) -> Result<Vec<u8>> {
        let mut input = [0u8; 5];
        input[..4].copy_from_slice(key);
        input[4] = size;
        let mut out = [0u8; 32];
        let ret = self.ioctl(IOCTL_READ_KEY, &input, &mut out)?;
        let n = (ret as usize).min(size as usize).min(out.len());
        Ok(out[..n].to_vec())
    }

    pub fn write_key(&self, key: &[u8; 4], data: &[u8]) -> Result<()> {
        let mut input = Vec::with_capacity(5 + data.len());
        input.extend_from_slice(key);
        input.push(data.len() as u8);
        input.extend_from_slice(data);
        let mut out = [0u8; 1];
        self.ioctl(IOCTL_WRITE_KEY, &input, &mut out)?;
        Ok(())
    }

    pub fn key_info(&self, key: &[u8; 4]) -> Result<KeyInfo> {
        let mut input = [0u8; 4];
        input.copy_from_slice(key);
        let mut out = [0u8; 8];
        let ret = self.ioctl(IOCTL_GET_KEY_INFO, &input, &mut out)?;
        if ret < 6 {
            return Err(SmcError::msg(format!(
                "get key info for {} returned {ret} bytes",
                key_to_string(key)
            )));
        }
        let a = [out[1], out[2], out[3], out[4]];
        let ty = if looks_like_type(&a) {
            a
        } else {
            [out[4], out[3], out[2], out[1]]
        };
        Ok(KeyInfo {
            size: out[0],
            ty,
            attrs: out[5],
        })
    }

    #[allow(dead_code)]
    pub fn key_by_index(&self, index: u32) -> Result<[u8; 4]> {
        let mut input = [0u8; 4];
        input.copy_from_slice(&index.to_ne_bytes());
        let mut out = [0u8; 4];
        let ret = self.ioctl(IOCTL_GET_KEY_BY_INDEX, &input, &mut out)?;
        if ret < 4 {
            return Err(SmcError::msg(format!(
                "key by index {index} returned {ret} bytes"
            )));
        }
        let mut key = [out[0], out[1], out[2], out[3]];
        if !key.iter().all(|b| b.is_ascii_graphic()) {
            key.reverse();
        }
        Ok(key)
    }

    /// Read a key whose size is discovered automatically.
    pub fn read_auto(&self, key: &[u8; 4]) -> Result<(KeyInfo, Vec<u8>)> {
        let info = self.key_info(key)?;
        let data = self.read_key(key, info.size)?;
        Ok((info, data))
    }

    pub fn key_count(&self) -> Result<u32> {
        let (info, data) = self.read_auto(b"#KEY")?;
        if data.len() < 4 {
            return Err(SmcError::msg(format!(
                "#KEY returned {} bytes (type {})",
                data.len(),
                info.type_str()
            )));
        }
        Ok(u32::from_be_bytes([data[0], data[1], data[2], data[3]]))
    }
}

impl Drop for Smc {
    fn drop(&mut self) {
        win::close_handle(self.handle);
    }
}

// ---- value decoding ------------------------------------------------------

pub fn decode_value(info: &KeyInfo, data: &[u8]) -> Option<f32> {
    if info.is_fpe2() && data.len() >= 2 {
        return Some(u16::from_be_bytes([data[0], data[1]]) as f32 / 4.0);
    }
    if info.is_float() && data.len() >= 4 {
        return Some(f32::from_be_bytes([data[0], data[1], data[2], data[3]]));
    }
    if &info.ty == b"sp78" && data.len() >= 2 {
        return Some(i16::from_be_bytes([data[0], data[1]]) as f32 / 256.0);
    }
    if &info.ty == b"sp87" && data.len() >= 2 {
        return Some(i16::from_be_bytes([data[0], data[1]]) as f32 / 128.0);
    }
    if &info.ty == b"si16" && data.len() >= 2 {
        return Some(i16::from_be_bytes([data[0], data[1]]) as f32);
    }
    if &info.ty == b"ui16" && data.len() >= 2 {
        return Some(u16::from_be_bytes([data[0], data[1]]) as f32);
    }
    if &info.ty == b"ui8 " && !data.is_empty() {
        return Some(data[0] as f32);
    }
    None
}

#[cfg(test)]
mod tests {
    use super::{decode_value, KeyInfo};

    #[test]
    fn decodes_signed_integer_temperature() {
        let info = KeyInfo { size: 2, ty: *b"si16", attrs: 0 };
        assert_eq!(decode_value(&info, &42i16.to_be_bytes()), Some(42.0));
        assert_eq!(decode_value(&info, &(-7i16).to_be_bytes()), Some(-7.0));
        assert_eq!(decode_value(&info, &[0]), None);
    }
}

pub fn encode_rpm(info: &KeyInfo, rpm: f32) -> Vec<u8> {
    let rpm = rpm.max(0.0);
    if info.is_float() {
        return rpm.to_be_bytes().to_vec();
    }
    // fpe2 / default
    let raw = (rpm * 4.0).round().clamp(0.0, u16::MAX as f32) as u16;
    raw.to_be_bytes().to_vec()
}
