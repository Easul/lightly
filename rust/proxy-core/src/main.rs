use tokio;

mod common;
mod inbound;
mod outbound;
mod pool;
mod ffi;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    common::init_logging("debug");
    
    log::info!("Proxy Core CLI starting...");
    
    let server = inbound::InboundServer::bind("127.0.0.1:23333").await?;
    server.run().await?;
    
    Ok(())
}
