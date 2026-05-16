use std::sync::Arc;
use tokio::net::TcpStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::Mutex;
use crate::common::Result;
use crate::outbound::vless::VlessClient;
use crate::pool::ConnectionPool;

pub async fn handle_socks5(
    mut stream: TcpStream,
    outbound: Option<Arc<VlessClient>>,
) -> Result<()> {
    let mut buf = [0u8; 2];
    stream.read_exact(&mut buf).await?;
    
    if buf[0] != 0x05 {
        return Err(crate::common::Error::Protocol(
            "Invalid SOCKS version".to_string()
        ));
    }
    
    let nmethods = buf[1] as usize;
    let mut methods = vec![0u8; nmethods];
    stream.read_exact(&mut methods).await?;
    
    if !methods.contains(&0x00) {
        stream.write_all(&[0x05, 0xFF]).await?;
        return Err(crate::common::Error::Protocol(
            "No supported authentication method".to_string()
        ));
    }
    
    stream.write_all(&[0x05, 0x00]).await?;
    
    let mut request = [0u8; 4];
    stream.read_exact(&mut request).await?;
    
    if request[0] != 0x05 || request[1] != 0x01 {
        stream.write_all(&[0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
        return Err(crate::common::Error::Protocol(
            "Invalid SOCKS request".to_string()
        ));
    }
    
    let addr = match request[3] {
        0x01 => {
            let mut addr = [0u8; 4];
            stream.read_exact(&mut addr).await?;
            format!("{}.{}.{}.{}", addr[0], addr[1], addr[2], addr[3])
        }
        0x03 => {
            let mut len = [0u8; 1];
            stream.read_exact(&mut len).await?;
            let mut domain = vec![0u8; len[0] as usize];
            stream.read_exact(&mut domain).await?;
            String::from_utf8_lossy(&domain).to_string()
        }
        0x04 => {
            return Err(crate::common::Error::NotSupported(
                "IPv6 not yet supported".to_string()
            ));
        }
        _ => {
            return Err(crate::common::Error::Protocol(
                "Invalid address type".to_string()
            ));
        }
    };
    
    let mut port = [0u8; 2];
    stream.read_exact(&mut port).await?;
    let port = ((port[0] as u16) << 8) | (port[1] as u16);
    
    log::info!("SOCKS5 connecting to {}:{}", addr, port);
    
    match outbound {
        Some(client) => {
            match client.connect(&addr, port).await {
                Ok(vless_stream) => {
                    stream.write_all(&[
                        0x05, 0x00, 0x00, 0x01,
                        0, 0, 0, 0,
                        (port >> 8) as u8,
                        (port & 0xFF) as u8,
                    ]).await?;
                    
                    let vless = Arc::new(Mutex::new(vless_stream));
                    let vless_clone = vless.clone();
                    
                    let (mut client_r, mut client_w) = stream.split();
                    
                    let c2v = async move {
                        let mut buf = [0u8; 4096];
                        loop {
                            match client_r.read(&mut buf).await {
                                Ok(0) => break,
                                Ok(n) => {
                                    if vless.lock().await.write(&buf[..n]).await.is_err() {
                                        break;
                                    }
                                }
                                Err(_) => break,
                            }
                        }
                    };
                    
                    let v2c = async move {
                        let mut buf = [0u8; 4096];
                        loop {
                            match vless_clone.lock().await.read(&mut buf).await {
                                Ok(0) => break,
                                Ok(n) => {
                                    if client_w.write_all(&buf[..n]).await.is_err() {
                                        break;
                                    }
                                }
                                Err(_) => break,
                            }
                        }
                        let _ = vless_clone.lock().await.close().await;
                    };
                    
                    tokio::select! {
                        _ = c2v => {},
                        _ = v2c => {},
                    }
                }
                Err(e) => {
                    log::error!("VLESS connection failed: {}", e);
                    stream.write_all(&[0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
                }
            }
        }
        None => {
            match TcpStream::connect(format!("{}:{}", addr, port)).await {
                Ok(target) => {
                    use std::net::SocketAddr;
                    let bind_addr = target.local_addr().unwrap_or_else(|_| {
                        SocketAddr::from(([127, 0, 0, 1], 0))
                    });
                    
                    stream.write_all(&[
                        0x05, 0x00, 0x00, 0x01,
                        0, 0, 0, 0,
                        (bind_addr.port() >> 8) as u8,
                        (bind_addr.port() & 0xFF) as u8,
                    ]).await?;
                    
                    pipe_bidirectional(stream, target).await;
                }
                Err(e) => {
                    stream.write_all(&[0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
                    return Err(e.into());
                }
            }
        }
    }
    
    Ok(())
}

async fn pipe_bidirectional(mut client: TcpStream, mut target: TcpStream) {
    let (mut client_r, mut client_w) = client.split();
    let (mut target_r, mut target_w) = target.split();
    
    let c2t = tokio::io::copy(&mut client_r, &mut target_w);
    let t2c = tokio::io::copy(&mut target_r, &mut client_w);
    
    match tokio::try_join!(c2t, t2c) {
        Ok((c2t_bytes, t2c_bytes)) => {
            log::debug!("SOCKS5 tunnel closed: {} bytes client→target, {} bytes target→client", c2t_bytes, t2c_bytes);
        }
        Err(e) => {
            log::debug!("SOCKS5 tunnel error: {}", e);
        }
    }
}
