pub mod http;
pub mod relay;
pub mod socks5;

use crate::common::Result;
use crate::pool::OutboundClientRegistry;
use std::sync::Arc;
use tokio::net::TcpListener;

pub struct InboundServer {
    listener: TcpListener,
    pool: Arc<OutboundClientRegistry>,
}

impl InboundServer {
    pub async fn bind(addr: &str, pool: Arc<OutboundClientRegistry>) -> Result<Self> {
        let listener = TcpListener::bind(addr).await?;
        log::info!("Inbound server listening on {}", addr);
        Ok(Self { listener, pool })
    }

    pub async fn run(self) -> Result<()> {
        loop {
            let (socket, addr) = self.listener.accept().await?;
            log::debug!("Accepted connection from {}", addr);
            let pool = self.pool.clone();

            tokio::spawn(async move {
                if let Err(e) = handle_connection(socket, pool).await {
                    log::error!("Connection handler error: {}", e);
                }
            });
        }
    }
}

async fn handle_connection(
    socket: tokio::net::TcpStream,
    pool: Arc<OutboundClientRegistry>,
) -> Result<()> {
    let peer_addr = socket
        .peer_addr()
        .unwrap_or_else(|_| "unknown".parse().unwrap());
    log::info!("[RustProxy] New connection from {}", peer_addr);

    let mut buf = [0u8; 1];
    let n = socket.peek(&mut buf).await?;

    if n == 0 {
        log::warn!("[RustProxy] Connection closed before data received");
        return Err(crate::common::Error::ConnectionClosed);
    }

    log::info!(
        "[RustProxy] First byte: 0x{:02x} (char: {})",
        buf[0],
        buf[0] as char
    );

    let client = pool.get_client("default").await;
    log::info!(
        "[RustProxy] Got outbound client: {}",
        if client.is_some() {
            "Some"
        } else {
            "None (direct mode)"
        }
    );

    match buf[0] {
        0x05 => {
            log::info!("[RustProxy] Routing to SOCKS5 handler");
            socks5::handle_socks5(socket, client).await
        }
        b'G' | b'P' | b'H' | b'D' | b'O' | b'T' | b'C' => {
            log::info!("[RustProxy] Routing to HTTP handler");
            http::handle_http(socket, client).await
        }
        _ => {
            log::error!("[RustProxy] Unknown protocol byte: 0x{:02x}", buf[0]);
            Err(crate::common::Error::Protocol(format!(
                "Unknown protocol byte: 0x{:02x}",
                buf[0]
            )))
        }
    }
}
