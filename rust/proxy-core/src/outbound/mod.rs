pub mod hysteria2;
pub mod vless;

use crate::common::Result;
use async_trait::async_trait;
use std::net::SocketAddr;
use std::sync::Arc;

#[async_trait]
pub trait OutboundClient: Send + Sync {
    async fn connect(&self, addr: &str, port: u16) -> Result<Arc<dyn ProxyStream>>;
}

#[async_trait]
pub trait ProxyStream: Send + Sync {
    async fn read(&self, buf: &mut [u8]) -> Result<usize>;
    async fn write(&self, buf: &[u8]) -> Result<()>;
    async fn close(&self) -> Result<()>;

    fn local_bind_addr(&self) -> Option<SocketAddr> {
        None
    }
}
