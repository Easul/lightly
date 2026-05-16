use crate::common::{Result, Error};
use bytes::BytesMut;
use std::net::SocketAddr;
use std::sync::Arc;
use sha2::{Sha256, Digest};

pub struct Hysteria2Client {
    config: Hysteria2Config,
}

#[derive(Debug, Clone)]
pub struct Hysteria2Config {
    pub server_addr: String,
    pub server_port: u16,
    pub password: String,
    pub sni: Option<String>,
    pub obfs: Option<String>,
}

pub struct Hysteria2Stream;

impl Hysteria2Client {
    pub fn new(config: Hysteria2Config) -> Self {
        Self { config }
    }

    pub async fn connect(&self, _target_addr: &str, _target_port: u16) -> Result<Hysteria2Stream> {
        let _server_addr = format!("{}:{}", self.config.server_addr, self.config.server_port);
        
        Err(Error::NotSupported(
            "Hysteria2 requires manual quinn-rustls integration. Use VLESS for now.".to_string()
        ))
    }
}

impl Hysteria2Stream {
    pub async fn read(&mut self, _buf: &mut [u8]) -> Result<usize> {
        Err(Error::ConnectionClosed)
    }

    pub async fn write(&mut self, _buf: &[u8]) -> Result<()> {
        Err(Error::ConnectionClosed)
    }

    pub async fn close(&mut self) -> Result<()> {
        Ok(())
    }
}

fn build_auth_request(target_addr: &str, target_port: u16, password: &str) -> Vec<u8> {
    let mut buf = BytesMut::new();
    
    buf.extend_from_slice(&[0x01]); 
    
    let auth = format!("{}:{}", target_addr, target_port);
    let auth_len = auth.len() as u8;
    buf.extend_from_slice(&[auth_len]);
    buf.extend_from_slice(auth.as_bytes());
    
    let mut hasher = Sha256::new();
    hasher.update(password.as_bytes());
    hasher.update(&[target_port as u8, (target_port >> 8) as u8]);
    hasher.update(target_addr.as_bytes());
    let hash = hasher.finalize();
    buf.extend_from_slice(&hash[..16]);
    
    buf.to_vec()
}
