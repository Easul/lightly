use std::sync::Arc;
use tokio;

mod common;
mod ffi;
mod inbound;
mod outbound;
mod pool;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    common::init_logging("debug");

    log::info!("Proxy Core CLI starting...");

    let pool = Arc::new(pool::ConnectionPool::new(100));
    let server = inbound::InboundServer::bind("127.0.0.1:23333", pool).await?;
    server.run().await?;

    Ok(())
}
