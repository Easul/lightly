use crate::common::Result;

pub struct VlessClient {
    config: VlessConfig,
}

#[derive(Debug, Clone)]
pub struct VlessConfig {
    pub uuid: String,
    pub server_addr: String,
    pub server_port: u16,
    pub security: SecurityType,
    pub host: Option<String>,
    pub sni: Option<String>,
    pub path: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum SecurityType {
    None,
    Tls,
    Xtls,
}

impl VlessClient {
    pub fn new(config: VlessConfig) -> Self {
        Self { config }
    }

    pub async fn connect(&self, _target_addr: &str, _target_port: u16) -> Result<VlessStream> {
        todo!("VLESS connection not yet implemented")
    }
}

pub struct VlessStream;

impl VlessStream {
    pub async fn read(&mut self, _buf: &mut [u8]) -> Result<usize> {
        todo!()
    }

    pub async fn write(&mut self, _buf: &[u8]) -> Result<()> {
        todo!()
    }

    pub async fn close(&mut self) -> Result<()> {
        todo!()
    }
}
