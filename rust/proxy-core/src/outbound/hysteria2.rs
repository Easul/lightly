use crate::common::Result;

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

impl Hysteria2Client {
    pub fn new(config: Hysteria2Config) -> Self {
        Self { config }
    }

    pub async fn connect(&self, _target_addr: &str, _target_port: u16) -> Result<Hysteria2Stream> {
        todo!("Hysteria2 connection not yet implemented")
    }
}

pub struct Hysteria2Stream;

impl Hysteria2Stream {
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
