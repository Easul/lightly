use std::env;
use std::str::FromStr;
use std::sync::Once;

pub mod error;

pub use error::{Error, Result};

static LOGGER_INIT: Once = Once::new();

pub fn init_logging(default_level: &str) {
    LOGGER_INIT.call_once(|| {
        let level = env::var("PROXY_CORE_LOG")
            .ok()
            .and_then(|s| log::LevelFilter::from_str(&s).ok())
            .unwrap_or_else(|| {
                log::LevelFilter::from_str(default_level).unwrap_or(log::LevelFilter::Info)
            });

        env_logger::Builder::new()
            .filter_level(level)
            .format_timestamp_millis()
            .init();
    });
}
