pub mod vless;
pub mod hysteria2;

use crate::common::Result;
use async_trait::async_trait;

#[async_trait]
pub trait OutboundClient: Send + Sync {
    async fn connect(&self, addr: &str, port: u16) -> Result<Box<dyn ProxyStream>>;
}

#[async_trait]
pub trait ProxyStream: Send {
    async fn read(&mut self, buf: &mut [u8]) -> Result<usize>;
    async fn write(&mut self, buf: &[u8]) -> Result<()>;
    async fn close(&mut self) -> Result<()>;
}
