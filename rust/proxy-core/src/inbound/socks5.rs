use std::sync::Arc;
use tokio::net::TcpStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::time::{sleep, Duration};
use crate::common::Result;
use crate::outbound::vless::VlessClient;

const AUTH_NONE: u8 = 0x00;
const AUTH_USERNAME_PASSWORD: u8 = 0x02;
const AUTH_NO_ACCEPTABLE: u8 = 0xFF;

pub async fn handle_socks5(
    mut stream: TcpStream,
    outbound: Option<Arc<VlessClient>>,
) -> Result<()> {
    let peer_addr = stream.peer_addr().unwrap_or_else(|_| "unknown".parse().unwrap());
    log::info!("[SOCKS5] New connection from {}", peer_addr);
    
    let mut buf = [0u8; 2];
    stream.read_exact(&mut buf).await?;
    log::debug!("[SOCKS5] Version: {}, Methods count: {}", buf[0], buf[1]);
    
    if buf[0] != 0x05 {
        log::warn!("[SOCKS5] Invalid SOCKS version: {}", buf[0]);
        return Err(crate::common::Error::Protocol(
            "Invalid SOCKS version".to_string()
        ));
    }
    
    let nmethods = buf[1] as usize;
    let mut methods = vec![0u8; nmethods];
    stream.read_exact(&mut methods).await?;
    log::debug!("[SOCKS5] Client offered auth methods: {:?}", methods);
    
    let selected_auth = if methods.contains(&AUTH_NONE) {
        log::debug!("[SOCKS5] Selecting NO AUTH (0x00)");
        AUTH_NONE
    } else if methods.contains(&AUTH_USERNAME_PASSWORD) {
        log::debug!("[SOCKS5] Selecting USERNAME/PASSWORD (0x02)");
        AUTH_USERNAME_PASSWORD
    } else {
        log::warn!("[SOCKS5] No acceptable auth method from client");
        stream.write_all(&[0x05, AUTH_NO_ACCEPTABLE]).await?;
        return Err(crate::common::Error::Protocol(
            "No supported authentication method".to_string()
        ));
    };
    
    stream.write_all(&[0x05, selected_auth]).await?;
    
    if selected_auth == AUTH_USERNAME_PASSWORD {
        let mut auth_ver = [0u8; 1];
        stream.read_exact(&mut auth_ver).await?;
        log::debug!("[SOCKS5] Auth version: {}", auth_ver[0]);
        if auth_ver[0] != 0x01 {
            stream.write_all(&[0x01, 0x01]).await?;
            return Err(crate::common::Error::Protocol("Invalid auth version".to_string()));
        }
        
        let mut ulen = [0u8; 1];
        stream.read_exact(&mut ulen).await?;
        let mut username = vec![0u8; ulen[0] as usize];
        stream.read_exact(&mut username).await?;
        
        let mut plen = [0u8; 1];
        stream.read_exact(&mut plen).await?;
        let mut password = vec![0u8; plen[0] as usize];
        stream.read_exact(&mut password).await?;
        
        log::debug!("[SOCKS5] Auth credentials received ({} bytes user, {} bytes pass)", ulen[0], plen[0]);
        stream.write_all(&[0x01, 0x00]).await?;
    }
    
    let mut request = [0u8; 4];
    stream.read_exact(&mut request).await?;
    log::debug!("[SOCKS5] Request: ver={}, cmd={}, atyp={}", request[0], request[1], request[3]);
    
    if request[0] != 0x05 || request[1] != 0x01 {
        log::warn!("[SOCKS5] Invalid request: ver={}, cmd={}", request[0], request[1]);
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
            let mut addr = [0u8; 16];
            stream.read_exact(&mut addr).await?;
            let segments = addr
                .chunks_exact(2)
                .map(|chunk| format!("{:x}", u16::from_be_bytes([chunk[0], chunk[1]])))
                .collect::<Vec<_>>();
            segments.join(":")
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
    
    log::info!("[SOCKS5] {} → Connecting to {}:{}", peer_addr, addr, port);
    
    match outbound {
        Some(client) => {
            match client.connect(&addr, port).await {
                Ok(vless_stream) => {
                    let bind_addr = vless_stream.local_bind_addr();
                    let bind_ip = bind_addr.map(|addr| addr.ip()).unwrap_or_else(|| "127.0.0.1".parse().unwrap());
                    let bind_port = bind_addr.map(|addr| addr.port()).unwrap_or(0);
                    let (reply_atyp, reply_addr_bytes) = match bind_ip {
                        std::net::IpAddr::V4(ipv4) => (0x01u8, ipv4.octets().to_vec()),
                        std::net::IpAddr::V6(ipv6) => (0x04u8, ipv6.octets().to_vec()),
                    };
                    stream.write_all(&[
                        0x05, 0x00, 0x00, reply_atyp,
                    ]).await?;
                    stream.write_all(&reply_addr_bytes).await?;
                    stream.write_all(&[
                        (bind_port >> 8) as u8,
                        (bind_port & 0xFF) as u8,
                    ]).await?;
                    stream.flush().await?;
                    log::info!("[SOCKS5] Reply bind {}:{}", bind_ip, bind_port);
                    
                    let vless = Arc::new(vless_stream);
                    let vless_clone = vless.clone();
                    let fallback_vless = vless.clone();
                    let cleanup_vless = vless.clone();
                    
                    let (mut client_r, mut client_w) = stream.split();
                     
                    log::info!("[SOCKS5] {} ↔ Starting bidirectional relay", peer_addr);
                    
                    let c2v = async move {
                        let mut buf = [0u8; 4096];
                        let mut total = 0usize;
                        loop {
                            match client_r.read(&mut buf).await {
                                Ok(0) => {
                                    log::info!("[SOCKS5] Client → VLESS: EOF (total {} bytes)", total);
                                    break;
                                }
                                Ok(n) => {
                                    total += n;
                                    log::trace!("[SOCKS5] Client → VLESS: {} bytes", n);
                                    if let Err(error) = vless.write(&buf[..n]).await {
                                        if !matches!(error, crate::common::Error::ConnectionClosed) {
                                            log::warn!("[SOCKS5] Client → VLESS: Write failed: {}", error);
                                        }
                                        break;
                                    }
                                }
                                Err(e) => {
                                    log::warn!("[SOCKS5] Client → VLESS: Read error {}", e);
                                    break;
                                }
                            }
                        }
                        log::debug!("[SOCKS5] Client → VLESS: Closed (total {} bytes)", total);
                    };
                    
                    let v2c = async move {
                        let mut buf = [0u8; 4096];
                        let mut total = 0usize;
                        sleep(Duration::from_millis(8)).await;
                        loop {
                            match vless_clone.read(&mut buf).await {
                                Ok(0) => {
                                    log::info!("[SOCKS5] VLESS → Client: EOF (total {} bytes)", total);
                                    break;
                                }
                                Ok(n) => {
                                    total += n;
                                    log::trace!("[SOCKS5] VLESS → Client: {} bytes", n);
                                    if client_w.write_all(&buf[..n]).await.is_err() {
                                        log::warn!("[SOCKS5] VLESS → Client: Write failed");
                                        break;
                                    }
                                }
                                Err(e) => {
                                    log::warn!("[SOCKS5] VLESS → Client: Read error {}", e);
                                    break;
                                }
                            }
                        }
                        let _ = client_w.shutdown().await;
                        log::debug!("[SOCKS5] VLESS → Client: Closed (total {} bytes)", total);
                    };

                    let handshake_fallback = tokio::spawn(async move {
                        sleep(Duration::from_millis(8)).await;
                        let _ = fallback_vless.send_handshake_if_needed().await;
                    });
                    
                    tokio::join!(c2v, v2c);
                    let _ = handshake_fallback.await;
                    let _ = cleanup_vless.close().await;
                    log::info!("[SOCKS5] {} ↔ Bidirectional relay completed", peer_addr);
                }
                Err(e) => {
                    log::error!("[SOCKS5] VLESS connection failed: {}", e);
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
