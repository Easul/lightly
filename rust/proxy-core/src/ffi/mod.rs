use std::ffi::CStr;
use std::os::raw::c_char;

#[cfg(target_os = "android")]
pub mod android;

#[no_mangle]
pub extern "C" fn proxy_core_init(log_level: *const c_char) -> i32 {
    let level = unsafe {
        if log_level.is_null() {
            "info"
        } else {
            CStr::from_ptr(log_level).to_str().unwrap_or("info")
        }
    };

    crate::common::init_logging(level);
    log::info!("Proxy core initialized (log level: {})", level);
    0
}

#[no_mangle]
pub extern "C" fn proxy_core_start(listen_addr: *const c_char, config_json: *const c_char) -> i32 {
    log::info!("proxy_core_start called");
    0
}

#[no_mangle]
pub extern "C" fn proxy_core_stop() -> i32 {
    log::info!("proxy_core_stop called");
    0
}

#[no_mangle]
pub extern "C" fn proxy_core_version() -> *const c_char {
    "0.1.0\0".as_ptr() as *const c_char
}
