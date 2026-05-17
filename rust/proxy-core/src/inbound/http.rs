use std::sync::Arc;
use tokio::net::TcpStream;
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::time::{sleep, Duration};
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
        let _headers = read_headers(&mut reader).await?;
        
        match outbound {
            Some(client) => {
                match client.connect(&addr, port).await {
                    Ok(vless_stream) => {
                        let remaining = reader.buffer().to_vec();
                        let mut stream = reader.into_inner();
                        stream.write_all(b"HTTP/1.1 200 Connection established\r\n\r\n").await?;
                        stream.flush().await?;
                        
                        let vless = Arc::new(vless_stream);
                        let vless_clone = vless.clone();
                        let fallback_vless = vless.clone();
                        let cleanup_vless = vless.clone();
                        
                        let (mut client_r, mut client_w) = stream.split();
                          
                        let c2v = async move {
                            let mut buf = [0u8; 4096];
                            if !remaining.is_empty() {
                                if let Err(e) = vless.write(&remaining).await {
                                    log::error!("Failed to forward buffered CONNECT payload via VLESS: {}", e);
                                    return;
                                }
                            }
                            loop {
                                match client_r.read(&mut buf).await {
                                    Ok(0) => {
                                        log::info!("HTTP CONNECT client -> VLESS EOF");
                                        break;
                                    }
                                    Ok(n) => {
                                        if let Err(error) = vless.write(&buf[..n]).await {
                                            if !matches!(error, crate::common::Error::ConnectionClosed) {
                                                log::warn!("HTTP CONNECT client -> VLESS write failed: {}", error);
                                            }
                                            break;
                                        }
                                    }
                                    Err(e) => {
                                        log::warn!("HTTP CONNECT client -> VLESS read error: {}", e);
                                        break;
                                    }
                                }
                            }
                        };
                        
                        let v2c = async move {
                            let mut buf = [0u8; 4096];
                            loop {
                                match vless_clone.read(&mut buf).await {
                                    Ok(0) => {
                                        log::info!("HTTP CONNECT VLESS -> client EOF");
                                        break;
                                    }
                                    Ok(n) => {
                                        if client_w.write_all(&buf[..n]).await.is_err() {
                                            log::warn!("HTTP CONNECT VLESS -> client write failed");
                                            break;
                                        }
                                    }
                                    Err(e) => {
                                        log::warn!("HTTP CONNECT VLESS -> client read error: {}", e);
                                        break;
                                    }
                                }
                            }
                            let _ = client_w.shutdown().await;
                        };

                        let handshake_fallback = tokio::spawn(async move {
                            sleep(Duration::from_millis(8)).await;
                            let _ = fallback_vless.send_handshake_if_needed().await;
                        });
                        
                        tokio::join!(c2v, v2c);
                        let _ = handshake_fallback.await;
                        let _ = cleanup_vless.close().await;
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
                        let _remaining = reader.buffer().to_vec();
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
                    Ok(vless_stream) => {
                        let remaining = reader.buffer().to_vec();
                        let mut stream = reader.into_inner();
                        
                        let normalized_request_line = normalize_http_proxy_request_line_for_origin(&request_line);
                        let request_bytes = build_http_request(&normalized_request_line, &headers, &remaining).await;
                        if let Err(e) = vless_stream.write(&request_bytes).await {
                            log::error!("Failed to send HTTP request via VLESS: {}", e);
                            return Ok(());
                        }
                        
                        let vless = Arc::new(vless_stream);
                        let vless_clone = vless.clone();
                        let cleanup_vless = vless.clone();
                        
                        let (mut client_r, mut client_w) = stream.split();
                        
                        let c2v = async move {
                            let mut buf = [0u8; 4096];
                            loop {
                                match client_r.read(&mut buf).await {
                                    Ok(0) => {
                                        log::info!("HTTP client -> VLESS EOF");
                                        break;
                                    }
                                    Ok(n) => {
                                        if let Err(error) = vless.write(&buf[..n]).await {
                                            if !matches!(error, crate::common::Error::ConnectionClosed) {
                                                log::warn!("HTTP client -> VLESS write failed: {}", error);
                                            }
                                            break;
                                        }
                                    }
                                    Err(e) => {
                                        log::warn!("HTTP client -> VLESS read error: {}", e);
                                        break;
                                    }
                                }
                            }
                        };
                        
                        let v2c = async move {
                            let mut buf = [0u8; 4096];
                            loop {
                                match vless_clone.read(&mut buf).await {
                                    Ok(0) => {
                                        log::info!("HTTP VLESS -> client EOF");
                                        break;
                                    }
                                    Ok(n) => {
                                        if client_w.write_all(&buf[..n]).await.is_err() {
                                            log::warn!("HTTP VLESS -> client write failed");
                                            break;
                                        }
                                    }
                                    Err(e) => {
                                        log::warn!("HTTP VLESS -> client read error: {}", e);
                                        break;
                                    }
                                }
                            }
                            let _ = client_w.shutdown().await;
                        };
                        
                        tokio::join!(c2v, v2c);
                        let _ = cleanup_vless.close().await;
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
                let remaining = reader.buffer().to_vec();
                
                let mut stream = reader.into_inner();
                let normalized_request_line = normalize_http_proxy_request_line_for_origin(&request_line);
                stream.write_all(normalized_request_line.as_bytes()).await?;
                stream.write_all(b"\r\n").await?;
                for (k, v) in &headers {
                    stream.write_all(format!("{}: {}\r\n", k, v).as_bytes()).await?;
                }
                stream.write_all(b"\r\n").await?;
                if !remaining.is_empty() {
                    stream.write_all(&remaining).await?;
                }
                
                pipe_bidirectional(stream, target).await;
            }
        }
    }
    
    Ok(())
}

async fn build_http_request(request_line: &str, headers: &[(String, String)], remaining: &[u8]) -> Vec<u8> {
    let mut buf = Vec::new();
    buf.extend_from_slice(request_line.as_bytes());
    buf.extend_from_slice(b"\r\n");
    for (k, v) in headers {
        buf.extend_from_slice(format!("{}: {}\r\n", k, v).as_bytes());
    }
    buf.extend_from_slice(b"\r\n");
    buf.extend_from_slice(remaining);
    buf
}

fn normalize_http_proxy_request_line_for_origin(request_line: &str) -> String {
    let parts: Vec<&str> = request_line.trim().split_whitespace().collect();
    if parts.len() < 3 {
        return request_line.trim().to_string();
    }

    let method = parts[0];
    let target = parts[1];
    let version = parts[2];

    let Ok(uri) = target.parse::<http::Uri>() else {
        return request_line.trim().to_string();
    };

    if uri.scheme().is_none() || uri.host().is_none() {
        return request_line.trim().to_string();
    }

    let mut origin_form = uri.path().to_string();
    if origin_form.is_empty() {
        origin_form = "/".to_string();
    }
    if let Some(query) = uri.query() {
        origin_form.push('?');
        origin_form.push_str(query);
    }

    format!("{} {} {}", method, origin_form, version)
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
