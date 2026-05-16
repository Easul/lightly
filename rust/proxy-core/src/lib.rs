pub mod common;
pub mod inbound;
pub mod outbound;
pub mod pool;
pub mod ffi;

use common::error::Result;
use std::ffi::CStr;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn proxy_core_init(log_level: *const c_char) -> i32 {
    let level = unsafe {
        if log_level.is_null() {
            "info"
        } else {
            CStr::from_ptr(log_level).to_str().unwrap_or("info")
        }
    };
    
    common::init_logging(level);
    log::info!("Proxy core initialized with log level: {}", level);
    0
}

#[no_mangle]
pub extern "C" fn proxy_core_version() -> *const c_char {
    "0.1.0\0".as_ptr() as *const c_char
}
