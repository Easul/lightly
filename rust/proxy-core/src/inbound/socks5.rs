use tokio::net::TcpStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use crate::common::Result;
use std::net::SocketAddr;

pub async fn handle_socks5(mut stream: TcpStream) -> Result<()> {
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
    
    match TcpStream::connect(format!("{}:{}", addr, port)).await {
        Ok(target) => {
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
