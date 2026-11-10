//! Minimal Win32 bindings used by the app (no external `windows` crate).

#![allow(non_snake_case)]

use std::ffi::OsStr;
use std::os::windows::ffi::OsStrExt;

pub type HANDLE = isize;

pub const INVALID_HANDLE_VALUE: HANDLE = -1;
pub const GENERIC_READ: u32 = 0x8000_0000;
pub const GENERIC_WRITE: u32 = 0x4000_0000;
pub const FILE_SHARE_READ: u32 = 0x0000_0001;
pub const FILE_SHARE_WRITE: u32 = 0x0000_0002;
pub const OPEN_EXISTING: u32 = 3;

pub const SC_MANAGER_CONNECT: u32 = 0x0001;
pub const SERVICE_QUERY_STATUS: u32 = 0x0004;
pub const SERVICE_START: u32 = 0x0010;

pub const ERROR_ACCESS_DENIED: u32 = 5;
pub const ERROR_FILE_NOT_FOUND: u32 = 2;
pub const ERROR_PATH_NOT_FOUND: u32 = 3;
pub const ERROR_SERVICE_ALREADY_RUNNING: u32 = 1056;
pub const ERROR_SERVICE_DOES_NOT_EXIST: u32 = 1060;

#[link(name = "kernel32")]
extern "system" {
    fn CreateFileW(
        lpFileName: *const u16,
        dwDesiredAccess: u32,
        dwShareMode: u32,
        lpSecurityAttributes: *mut core::ffi::c_void,
        dwCreationDisposition: u32,
        dwFlagsAndAttributes: u32,
        hTemplateFile: HANDLE,
    ) -> HANDLE;

    fn DeviceIoControl(
        hDevice: HANDLE,
        dwIoControlCode: u32,
        lpInBuffer: *mut core::ffi::c_void,
        nInBufferSize: u32,
        lpOutBuffer: *mut core::ffi::c_void,
        nOutBufferSize: u32,
        lpBytesReturned: *mut u32,
        lpOverlapped: *mut core::ffi::c_void,
    ) -> i32;

    fn CloseHandle(hObject: HANDLE) -> i32;
    fn GetLastError() -> u32;
}

#[link(name = "advapi32")]
extern "system" {
    fn OpenSCManagerW(
        lpMachineName: *const u16,
        lpDatabaseName: *const u16,
        dwDesiredAccess: u32,
    ) -> HANDLE;
    fn OpenServiceW(hSCManager: HANDLE, lpServiceName: *const u16, dwDesiredAccess: u32) -> HANDLE;
    fn StartServiceW(hService: HANDLE, dwNumServiceArgs: u32, lpServiceArgVectors: *const *const u16) -> i32;
    fn CloseServiceHandle(hSCObject: HANDLE) -> i32;
}

#[link(name = "shell32")]
extern "system" {
    fn IsUserAnAdmin() -> i32;
    fn ShellExecuteW(
        hwnd: isize,
        lpOperation: *const u16,
        lpFile: *const u16,
        lpParameters: *const u16,
        lpDirectory: *const u16,
        nShowCmd: i32,
    ) -> isize;
}

pub fn wide(s: &str) -> Vec<u16> {
    OsStr::new(s).encode_wide().chain(std::iter::once(0)).collect()
}

pub fn last_error() -> u32 {
    unsafe { GetLastError() }
}

pub fn is_elevated() -> bool {
    unsafe { IsUserAnAdmin() != 0 }
}

/// Re-launch this executable with the UAC "runas" verb. Returns true if the
/// shell accepted the request.
pub fn relaunch_elevated() -> bool {
    let exe = match std::env::current_exe() {
        Ok(p) => p,
        Err(_) => return false,
    };
    let op = wide("runas");
    let file = wide(&exe.to_string_lossy());
    let args = std::env::args().skip(1).collect::<Vec<_>>().join(" ");
    let params = if args.is_empty() { None } else { Some(wide(&args)) };
    let r = unsafe {
        ShellExecuteW(
            0,
            op.as_ptr(),
            file.as_ptr(),
            params.as_ref().map_or(std::ptr::null(), |v| v.as_ptr()),
            std::ptr::null(),
            1, // SW_SHOWNORMAL
        )
    };
    r as usize > 32
}

pub fn open_device(path: &str) -> Result<HANDLE, u32> {
    let name = wide(path);
    let h = unsafe {
        CreateFileW(
            name.as_ptr(),
            GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            std::ptr::null_mut(),
            OPEN_EXISTING,
            0,
            0,
        )
    };
    if h == INVALID_HANDLE_VALUE {
        Err(last_error())
    } else {
        Ok(h)
    }
}

pub fn device_io_control(
    handle: HANDLE,
    code: u32,
    input: &[u8],
    output: &mut [u8],
) -> Result<u32, u32> {
    let mut returned: u32 = 0;
    let ok = unsafe {
        DeviceIoControl(
            handle,
            code,
            input.as_ptr() as *mut core::ffi::c_void,
            input.len() as u32,
            output.as_mut_ptr() as *mut core::ffi::c_void,
            output.len() as u32,
            &mut returned,
            std::ptr::null_mut(),
        )
    };
    if ok == 0 {
        Err(last_error())
    } else {
        Ok(returned)
    }
}

pub fn close_handle(handle: HANDLE) {
    unsafe {
        CloseHandle(handle);
    }
}

/// Try to start an already-installed kernel driver service (e.g. "AppleSMC").
/// Returns Ok(()) when the service is running or was started.
pub fn ensure_service_running(name: &str) -> Result<(), u32> {
    let scm = unsafe { OpenSCManagerW(std::ptr::null(), std::ptr::null(), SC_MANAGER_CONNECT) };
    if scm == 0 {
        return Err(last_error());
    }
    let svc_name = wide(name);
    let svc = unsafe {
        OpenServiceW(
            scm,
            svc_name.as_ptr(),
            SERVICE_START | SERVICE_QUERY_STATUS,
        )
    };
    if svc == 0 {
        let e = last_error();
        unsafe {
            CloseServiceHandle(scm);
        }
        return Err(e);
    }
    let ok = unsafe { StartServiceW(svc, 0, std::ptr::null()) };
    let err = if ok != 0 { 0 } else { last_error() };
    unsafe {
        CloseServiceHandle(svc);
        CloseServiceHandle(scm);
    }
    if ok != 0 || err == ERROR_SERVICE_ALREADY_RUNNING {
        Ok(())
    } else {
        Err(err)
    }
}

pub fn error_hint(code: u32) -> &'static str {
    match code {
        ERROR_ACCESS_DENIED => {
            "Access denied: quit Macs Fan Control (it opens the SMC device exclusively). If the AppleSMC driver service is stopped, restart this app as administrator."
        }
        ERROR_FILE_NOT_FOUND | ERROR_PATH_NOT_FOUND => {
            "The AppleSMC device/driver was not found. Install Macs Fan Control once (it provides the signed applesmc.sys driver), then retry."
        }
        ERROR_SERVICE_DOES_NOT_EXIST => {
            "The AppleSMC driver service is not installed. Install Macs Fan Control once to provide applesmc.sys, then retry."
        }
        ERROR_SERVICE_ALREADY_RUNNING => "Service already running.",
        _ => "",
    }
}
