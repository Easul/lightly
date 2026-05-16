use std::sync::Arc;
use tokio::net::TcpStream;
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::sync::Mutex;
use crate::common::Result;
use crate::outbound::vless::VlessClient;

pub async fn handle_http(
    stream: TcpStream,
    outbound: Option<Arc<VlessClient>>,
) -> Result<()> {
    let mut reader = BufReader::new(stream);
    let mut request_line = String::new();
    
    reader.read_line(&mut request_line).await?;
    
    let parts: Vec<&str> = request_line.trim().split_whitespace().collect();
    if parts.len() < 3 {
        return Err(crate::common::Error::Protocol(
            "Invalid HTTP request line".to_string()
        ));
    }
    
    let method = parts[0];
    let target = parts[1];
    
    log::info!("HTTP {} {}", method, target);
    
    if method == "CONNECT" {
        let (addr, port) = parse_target(target)?;
        log::info!("HTTP CONNECT to {}:{}", addr, port);
        
        match outbound {
            Some(client) => {
                match client.connect(&addr, port).await {
                    Ok(vless_stream) => {
                        let mut stream = reader.into_inner();
                        stream.write_all(b"HTTP/1.1 200 Connection established\r\n\r\n").await?;
                        
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
                        let mut stream = reader.into_inner();
                        stream.write_all(b"HTTP/1.1 502 Bad Gateway\r\n\r\n").await?;
                    }
                }
            }
            None => {
                match TcpStream::connect(format!("{}:{}", addr, port)).await {
                    Ok(target) => {
                        let mut stream = reader.into_inner();
                        stream.write_all(b"HTTP/1.1 200 Connection established\r\n\r\n").await?;
                        pipe_bidirectional(stream, target).await;
                    }
                    Err(_) => {
                        let mut stream = reader.into_inner();
                        stream.write_all(b"HTTP/1.1 502 Bad Gateway\r\n\r\n").await?;
                    }
                }
            }
        }
    } else {
        let headers = read_headers(&mut reader).await?;
        let host = headers.iter()
            .find(|(k, _)| k.eq_ignore_ascii_case("host"))
            .map(|(_, v)| v.clone())
            .ok_or_else(|| crate::common::Error::Protocol("Missing Host header".to_string()))?;
        
        let (addr, port) = parse_target_with_default_port(&host, 80)?;
        
        match outbound {
            Some(client) => {
                match client.connect(&addr, port).await {
                    Ok(mut vless_stream) => {
                        let mut stream = reader.into_inner();
                        
                        let request_bytes = build_http_request(&request_line, &headers).await;
                        if let Err(e) = vless_stream.write(&request_bytes).await {
                            log::error!("Failed to send HTTP request via VLESS: {}", e);
                            return Ok(());
                        }
                        
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
                        let mut stream = reader.into_inner();
                        stream.write_all(b"HTTP/1.1 502 Bad Gateway\r\n\r\n").await?;
                    }
                }
            }
            None => {
                let mut target = TcpStream::connect(format!("{}:{}", addr, port)).await?;
                
                let mut stream = reader.into_inner();
                stream.write_all(request_line.as_bytes()).await?;
                stream.write_all(b"\r\n").await?;
                for (k, v) in &headers {
                    stream.write_all(format!("{}: {}\r\n", k, v).as_bytes()).await?;
                }
                stream.write_all(b"\r\n").await?;
                
                pipe_bidirectional(stream, target).await;
            }
        }
    }
    
    Ok(())
}

async fn build_http_request(request_line: &str, headers: &[(String, String)]) -> Vec<u8> {
    let mut buf = Vec::new();
    buf.extend_from_slice(request_line.as_bytes());
    buf.extend_from_slice(b"\r\n");
    for (k, v) in headers {
        buf.extend_from_slice(format!("{}: {}\r\n", k, v).as_bytes());
    }
    buf.extend_from_slice(b"\r\n");
    buf
}

fn parse_target(target: &str) -> Result<(String, u16)> {
    if target.starts_with("http://") || target.starts_with("https://") {
        let url = target.splitn(2, "://").nth(1).unwrap_or(target);
        return parse_target_with_default_port(url, 443);
    }
    if let Some(colon_pos) = target.rfind(':') {
        let (addr, port_str) = target.split_at(colon_pos);
        if let Ok(port) = port_str[1..].parse::<u16>() {
            return Ok((addr.to_string(), port));
        }
    }
    Ok((target.to_string(), 443))
}

fn parse_target_with_default_port(target: &str, default_port: u16) -> Result<(String, u16)> {
    if let Some(colon_pos) = target.rfind(':') {
        let (addr, port_str) = target.split_at(colon_pos);
        if let Ok(port) = port_str[1..].parse::<u16>() {
            return Ok((addr.to_string(), port));
        }
    }
    Ok((target.to_string(), default_port))
}

async fn read_headers(reader: &mut BufReader<TcpStream>) -> Result<Vec<(String, String)>> {
    let mut headers = Vec::new();
    loop {
        let mut line = String::new();
        reader.read_line(&mut line).await?;
        let line = line.trim();
        if line.is_empty() {
            break;
        }
        if let Some(colon_pos) = line.find(':') {
            let key = line[..colon_pos].trim().to_string();
            let value = line[colon_pos + 1..].trim().to_string();
            headers.push((key, value));
        }
    }
    Ok(headers)
}

async fn pipe_bidirectional(mut client: TcpStream, mut target: TcpStream) {
    let (mut client_r, mut client_w) = client.split();
    let (mut target_r, mut target_w) = target.split();
    
    let c2t = tokio::io::copy(&mut client_r, &mut target_w);
    let t2c = tokio::io::copy(&mut target_r, &mut client_w);
    
    match tokio::try_join!(c2t, t2c) {
        Ok((c2t_bytes, t2c_bytes)) => {
            log::debug!("HTTP tunnel closed: {} bytes client→target, {} bytes target→client", c2t_bytes, t2c_bytes);
        }
        Err(e) => {
            log::debug!("HTTP tunnel error: {}", e);
        }
    }
}
