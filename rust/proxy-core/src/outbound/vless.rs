use crate::common::Result;
use crate::common::Error;
use bytes::{Bytes, BytesMut};
use futures::{SinkExt, StreamExt};
use tokio::net::TcpStream;
use tokio::sync::Mutex;
use tokio_tungstenite::{connect_async, tungstenite::Message, WebSocketStream, MaybeTlsStream};
use http;

pub struct VlessClient {
    config: VlessConfig,
}

#[derive(Debug, Clone)]
pub struct VlessConfig {
    pub uuid: String,
    pub server_addr: String,
    pub server_port: u16,
    pub security: SecurityType,
    pub host: Option<String>,
    pub sni: Option<String>,
    pub path: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum SecurityType {
    None,
    Tls,
}

pub struct VlessStream {
    ws: Arc<Mutex<WebSocketStream<MaybeTlsStream<TcpStream>>>>,
    read_buffer: BytesMut,
    uuid: [u8; 16],
    target_addr: String,
    target_port: u16,
    handshake_done: bool,
}

use std::sync::Arc;

impl VlessClient {
    pub fn new(config: VlessConfig) -> Self {
        Self { config }
    }

    pub async fn connect(&self, target_addr: &str, target_port: u16) -> Result<VlessStream> {
        let uuid_bytes = parse_uuid(&self.config.uuid)?;
        
        let host = self.config.host.as_ref()
            .unwrap_or(&self.config.server_addr);
        let sni = self.config.sni.as_ref()
            .unwrap_or(host);
        
        let ws_url = format!(
            "wss://{}:{}{}",
            self.config.server_addr,
            self.config.server_port,
            self.config.path
        );
        
        let mut request = http::Request::builder()
            .uri(&ws_url)
            .header("Host", host)
            .header("Upgrade", "websocket")
            .header("Connection", "Upgrade")
            .header("Sec-WebSocket-Key", generate_sec_websocket_key())
            .header("Sec-WebSocket-Version", "13");
        
        if let Some(ref sni_value) = self.config.sni {
            request = request.header("SNI", sni_value);
        }
        
        let (ws, _) = connect_async(request.body(()).unwrap())
            .await
            .map_err(|e| Error::Network(format!("WebSocket connection failed: {}", e)))?;
        
        let stream = VlessStream {
            ws: Arc::new(Mutex::new(ws)),
            read_buffer: BytesMut::new(),
            uuid: uuid_bytes,
            target_addr: target_addr.to_string(),
            target_port,
            handshake_done: false,
        };
        
        Ok(stream)
    }
}

impl VlessStream {
    async fn ensure_handshake(&mut self) -> Result<()> {
        if self.handshake_done {
            return Ok(());
        }
        
        let request = build_vless_request(
            &self.uuid,
            &self.target_addr,
            self.target_port,
        );
        
        let mut ws = self.ws.lock().await;
        ws.send(Message::Binary(request.to_vec())).await
            .map_err(|e| Error::Network(format!("WebSocket send failed: {}", e)))?;
        
        self.handshake_done = true;
        Ok(())
    }

    pub async fn read(&mut self, buf: &mut [u8]) -> Result<usize> {
        self.ensure_handshake().await?;
        
        if !self.read_buffer.is_empty() {
            let len = std::cmp::min(buf.len(), self.read_buffer.len());
            buf[..len].copy_from_slice(&self.read_buffer.split_to(len));
            return Ok(len);
        }
        
        let mut ws = self.ws.lock().await;
        
        loop {
            match ws.next().await {
                Some(Ok(Message::Binary(data))) => {
                    if data.is_empty() {
                        continue;
                    }
                    let len = std::cmp::min(buf.len(), data.len());
                    buf[..len].copy_from_slice(&data[..len]);
                    if data.len() > len {
                        self.read_buffer.extend_from_slice(&data[len..]);
                    }
                    return Ok(len);
                }
                Some(Ok(Message::Close(_))) => return Ok(0),
                Some(Err(e)) => {
                    return Err(Error::Network(format!("WebSocket error: {}", e)));
                }
                _ => continue,
            }
        }
    }

    pub async fn write(&mut self, buf: &[u8]) -> Result<()> {
        self.ensure_handshake().await?;
        
        let mut ws = self.ws.lock().await;
        ws.send(Message::Binary(buf.to_vec())).await
            .map_err(|e| Error::Network(format!("WebSocket send failed: {}", e)))?;
        
        Ok(())
    }

    pub async fn close(&mut self) -> Result<()> {
        let mut ws = self.ws.lock().await;
        let _ = ws.close(None).await;
        Ok(())
    }
}

pub fn parse_uuid(uuid_str: &str) -> Result<[u8; 16]> {
    let hex_str = uuid_str.replace("-", "");
    if hex_str.len() != 32 {
        return Err(Error::InvalidConfig("Invalid UUID format".to_string()));
    }
    
    let mut bytes = [0u8; 16];
    for i in 0..16 {
        bytes[i] = u8::from_str_radix(&hex_str[i*2..i*2+2], 16)
            .map_err(|_| Error::InvalidConfig("Invalid UUID hex".to_string()))?;
    }
    
    Ok(bytes)
}

fn generate_sec_websocket_key() -> String {
    use rand::Rng;
    let mut bytes = [0u8; 16];
    rand::thread_rng().fill(&mut bytes);
    base64::encode(&bytes)
}

pub fn build_vless_request(uuid: &[u8; 16], addr: &str, port: u16) -> Bytes {
    let mut buf = BytesMut::new();
    
    buf.extend_from_slice(&[0x00]);
    buf.extend_from_slice(uuid);
    buf.extend_from_slice(&[0x00]);
    
    if let Ok(ip) = addr.parse::<std::net::Ipv4Addr>() {
        buf.extend_from_slice(&[0x01]);
        buf.extend_from_slice(&ip.octets());
    } else if let Ok(ip) = addr.parse::<std::net::Ipv6Addr>() {
        buf.extend_from_slice(&[0x04]);
        buf.extend_from_slice(&ip.octets());
    } else {
        buf.extend_from_slice(&[0x03]);
        buf.extend_from_slice(&[addr.len() as u8]);
        buf.extend_from_slice(addr.as_bytes());
    }
    
    buf.extend_from_slice(&[(port >> 8) as u8, (port & 0xFF) as u8]);
    
    buf.freeze()
}

mod base64 {
    use base64::prelude::*;
    
    pub fn encode(input: &[u8]) -> String {
        BASE64_STANDARD.encode(input)
    }
}
