use std::fmt;
use std::io;

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug)]
pub enum Error {
    Io(io::Error),
    InvalidConfig(String),
    Protocol(String),
    Network(String),
    Tls(String),
    WebSocket(String),
    NotSupported(String),
    Timeout,
    ConnectionClosed,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Io(e) => write!(f, "IO error: {}", e),
            Error::InvalidConfig(s) => write!(f, "Invalid config: {}", s),
            Error::Protocol(s) => write!(f, "Protocol error: {}", s),
            Error::Network(s) => write!(f, "Network error: {}", s),
            Error::Tls(s) => write!(f, "TLS error: {}", s),
            Error::WebSocket(s) => write!(f, "WebSocket error: {}", s),
            Error::NotSupported(s) => write!(f, "Not supported: {}", s),
            Error::Timeout => write!(f, "Operation timed out"),
            Error::ConnectionClosed => write!(f, "Connection closed"),
        }
    }
}

impl std::error::Error for Error {}

impl From<io::Error> for Error {
    fn from(e: io::Error) -> Self {
        Error::Io(e)
    }
}

impl From<serde_json::Error> for Error {
    fn from(e: serde_json::Error) -> Self {
        Error::InvalidConfig(e.to_string())
    }
}
