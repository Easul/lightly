pub mod socks5;
pub mod http;

use tokio::net::TcpListener;
use crate::common::Result;
use crate::pool::ConnectionPool;
use std::sync::Arc;

pub struct InboundServer {
    listener: TcpListener,
    pool: Arc<ConnectionPool>,
}

impl InboundServer {
    pub async fn bind(addr: &str, pool: Arc<ConnectionPool>) -> Result<Self> {
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
    mut socket: tokio::net::TcpStream,
    pool: Arc<ConnectionPool>,
) -> Result<()> {
    let mut buf = [0u8; 1];
    let n = socket.peek(&mut buf).await?;
    
    if n == 0 {
        return Err(crate::common::Error::ConnectionClosed);
    }
    
    let client = pool.get_client("default").await;
    
    match buf[0] {
        0x05 => {
            log::debug!("SOCKS5 protocol detected");
            socks5::handle_socks5(socket, client).await
        }
        b'G' | b'P' | b'H' | b'D' | b'O' | b'T' | b'C' => {
            log::debug!("HTTP protocol detected");
            http::handle_http(socket, client).await
        }
        _ => {
            Err(crate::common::Error::Protocol(
                format!("Unknown protocol byte: 0x{:02x}", buf[0])
            ))
        }
    }
}
