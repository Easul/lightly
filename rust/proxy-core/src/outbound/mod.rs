pub mod hysteria2;
pub mod vless;
pub mod vless_codec;
pub mod vless_handshake;
pub mod vless_message_io;
pub mod vless_stream_state;
pub mod vless_transport;

use crate::common::Result;
use async_trait::async_trait;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

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

    fn first_downstream_grace(&self) -> Duration {
        Duration::from_millis(100)
    }
}
