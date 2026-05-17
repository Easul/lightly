use crate::common::Result;
use crate::common::Error;
use bytes::{Bytes, BytesMut};
use futures::{stream::{SplitSink, SplitStream}, SinkExt, StreamExt};
use rustls_022::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls_022::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls_022::{ClientConfig, DigitallySignedStruct, RootCertStore, SignatureScheme};
use tokio::net::{lookup_host, TcpStream};
use tokio::sync::Mutex;
use tokio::time::{timeout, Duration};
use tokio_tungstenite::{client_async_tls_with_config, tungstenite::Message, Connector, WebSocketStream, MaybeTlsStream};
use http;
use std::net::SocketAddr;

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
    pub tls_insecure: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum SecurityType {
    None,
    Tls,
}

pub struct VlessStream {
    write_half: Arc<Mutex<SplitSink<WebSocketStream<MaybeTlsStream<TcpStream>>, Message>>>,
    read_half: Arc<Mutex<SplitStream<WebSocketStream<MaybeTlsStream<TcpStream>>>>>,
    state: Mutex<VlessStreamState>,
    handshake_lock: Mutex<()>,
    uuid: [u8; 16],
    target_addr: String,
    target_port: u16,
    local_bind_addr: Option<SocketAddr>,
}

struct VlessStreamState {
    read_buffer: BytesMut,
    handshake_done: bool,
    response_header_pending: bool,
    response_header_buffer: BytesMut,
    remote_closed: bool,
}

use std::sync::Arc;

impl VlessClient {
    pub fn new(config: VlessConfig) -> Self {
        Self { config }
    }

    pub async fn connect(&self, target_addr: &str, target_port: u16) -> Result<VlessStream> {
        log::info!("[VLESS] Connecting to target {}:{}", target_addr, target_port);
        log::info!("[VLESS] Server: {}:{}", self.config.server_addr, self.config.server_port);
        
        let uuid_bytes = parse_uuid(&self.config.uuid)?;
        log::debug!("[VLESS] UUID parsed successfully");
        
        let use_tls = self.config.security == SecurityType::Tls;
        let ws_host = non_empty_str(self.config.host.as_deref());
        let tls_server_name = non_empty_str(self.config.sni.as_deref())
            .or(ws_host)
            .unwrap_or(&self.config.server_addr);
        let request_uri_host = if use_tls {
            tls_server_name
        } else {
            &self.config.server_addr
        };
        let ws_url = format!(
            "{}://{}:{}{}",
            if use_tls { "wss" } else { "ws" },
            request_uri_host,
            self.config.server_port,
            self.config.path
        );
        log::info!("[VLESS] WebSocket URL: {}", ws_url);
        
        let http_host = ws_host.unwrap_or(tls_server_name);
        let host_header = build_websocket_host_header(
            http_host,
            self.config.server_port,
            use_tls,
        );
        log::debug!("[VLESS] Host header: {}", host_header);
        log::debug!("[VLESS] TLS server name: {}", tls_server_name);
        
        let request = http::Request::builder()
            .uri(&ws_url)
            .header("Host", host_header)
            .header("Upgrade", "websocket")
            .header("Connection", "Upgrade")
            .header("Sec-WebSocket-Key", generate_sec_websocket_key())
            .header("Sec-WebSocket-Version", "13")
            .body(())
            .map_err(|e| Error::InvalidConfig(format!("Invalid WebSocket request: {}", e)))?;
        
        let tcp_addr = format!("{}:{}", self.config.server_addr, self.config.server_port);
        log::info!("[VLESS] Initiating WebSocket connection over TCP {}...", tcp_addr);
        let socket = connect_tcp_with_fallback(&self.config.server_addr, self.config.server_port).await?;
        let local_bind_addr = socket.local_addr().ok();

        let connector = if use_tls {
            Some(Connector::Rustls(build_rustls_config(&self.config)?))
        } else {
            Some(Connector::Plain)
        };

        let (ws, _) = timeout(
            Duration::from_secs(15),
            client_async_tls_with_config(request, socket, None, connector),
        )
            .await
            .map_err(|_| {
                log::error!("[VLESS] WebSocket connection timed out");
                Error::Timeout
            })?
            .map_err(|e| {
                log::error!("[VLESS] WebSocket connection failed: {}", e);
                Error::Network(format!("WebSocket connection failed: {}", e))
            })?;
        
        log::info!("[VLESS] WebSocket connected successfully");
        
        let (write_half, read_half) = ws.split();

        let stream = VlessStream {
            write_half: Arc::new(Mutex::new(write_half)),
            read_half: Arc::new(Mutex::new(read_half)),
            state: Mutex::new(VlessStreamState {
                read_buffer: BytesMut::new(),
                handshake_done: false,
                response_header_pending: true,
                response_header_buffer: BytesMut::new(),
                remote_closed: false,
            }),
            handshake_lock: Mutex::new(()),
            uuid: uuid_bytes,
            target_addr: target_addr.to_string(),
            target_port,
            local_bind_addr,
        };
        
        log::info!("[VLESS] Stream created for {}:{}", target_addr, target_port);
        Ok(stream)
    }
}

fn build_rustls_config(config: &VlessConfig) -> Result<std::sync::Arc<ClientConfig>> {
    let mut roots = RootCertStore::empty();
    roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());

    let mut client_config = ClientConfig::builder()
        .with_root_certificates(roots)
        .with_no_client_auth();

    if config.tls_insecure {
        client_config
            .dangerous()
            .set_certificate_verifier(std::sync::Arc::new(NoCertificateVerification));
    }

    Ok(std::sync::Arc::new(client_config))
}

fn build_websocket_host_header(http_host: &str, port: u16, use_tls: bool) -> String {
    let trimmed = http_host.trim();
    if trimmed.is_empty() {
        return String::new();
    }

    if has_explicit_port(trimmed) {
        return trimmed.to_string();
    }

    let default_port = if use_tls { 443 } else { 80 };
    if port == default_port {
        return trimmed.to_string();
    }

    if trimmed.contains(':') && !(trimmed.starts_with('[') && trimmed.ends_with(']')) {
        format!("[{}]:{}", trimmed, port)
    } else {
        format!("{}:{}", trimmed, port)
    }
}

fn has_explicit_port(host: &str) -> bool {
    if host.starts_with('[') {
        if let Some(closing) = host.rfind(']') {
            return closing < host.len() - 1 && host.as_bytes().get(closing + 1) == Some(&b':');
        }
    }
    host.matches(':').count() == 1
}

#[derive(Debug)]
struct NoCertificateVerification;

impl ServerCertVerifier for NoCertificateVerification {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> std::result::Result<ServerCertVerified, rustls_022::Error> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, rustls_022::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, rustls_022::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        vec![
            SignatureScheme::RSA_PKCS1_SHA1,
            SignatureScheme::ECDSA_SHA1_Legacy,
            SignatureScheme::RSA_PKCS1_SHA256,
            SignatureScheme::ECDSA_NISTP256_SHA256,
            SignatureScheme::RSA_PKCS1_SHA384,
            SignatureScheme::ECDSA_NISTP384_SHA384,
            SignatureScheme::RSA_PKCS1_SHA512,
            SignatureScheme::ECDSA_NISTP521_SHA512,
            SignatureScheme::RSA_PSS_SHA256,
            SignatureScheme::RSA_PSS_SHA384,
            SignatureScheme::RSA_PSS_SHA512,
            SignatureScheme::ED25519,
            SignatureScheme::ED448,
        ]
    }
}

impl VlessStream {
    async fn mark_remote_closed(&self) {
        let mut state = self.state.lock().await;
        state.remote_closed = true;
    }

    async fn is_remote_closed(&self) -> bool {
        let state = self.state.lock().await;
        state.remote_closed
    }

    fn consume_response_header(state: &mut VlessStreamState, chunk: &[u8]) -> Option<Vec<u8>> {
        if !state.response_header_pending {
            return Some(chunk.to_vec());
        }

        state.response_header_buffer.extend_from_slice(chunk);
        if state.response_header_buffer.len() < 2 {
            return None;
        }

        let addons_length = state.response_header_buffer[1] as usize;
        let header_length = 2 + addons_length;
        if state.response_header_buffer.len() < header_length {
            return None;
        }

        let payload = state.response_header_buffer.split_off(header_length).to_vec();
        state.response_header_buffer.clear();
        state.response_header_pending = false;
        Some(payload)
    }

    async fn ensure_handshake(&self, first_data: Option<&[u8]>) -> Result<bool> {
        {
            let state = self.state.lock().await;
            if state.handshake_done {
                return Ok(false);
            }
        }

        let _guard = self.handshake_lock.lock().await;
        {
            let state = self.state.lock().await;
            if state.handshake_done {
                return Ok(false);
            }
        }

        log::info!("[VLESS] Performing handshake to {}:{} (first_data: {})",
            self.target_addr, self.target_port, first_data.map(|d| d.len()).unwrap_or(0));

        let mut vless_request = build_vless_request(
            &self.uuid,
            &self.target_addr,
            self.target_port,
        );
        log::debug!(
            "[VLESS] Request bytes len={} hex={}",
            vless_request.len(),
            format_bytes_hex(&vless_request),
        );

        if let Some(data) = first_data {
            let mut combined = Vec::with_capacity(vless_request.len() + data.len());
            combined.extend_from_slice(&vless_request);
            combined.extend_from_slice(data);
            vless_request = Bytes::from(combined);
            log::debug!(
                "[VLESS] Combined handshake + first data: total={} request={} payload={}",
                vless_request.len(),
                vless_request.len() - data.len(),
                data.len(),
            );
        }

        let mut write_half = self.write_half.lock().await;
        write_half.send(Message::Binary(vless_request.to_vec())).await
            .map_err(|e| {
                log::error!("[VLESS] Handshake send failed: {}", e);
                Error::Network(format!("WebSocket send failed: {}", e))
            })?;

        log::info!("[VLESS] Handshake sent successfully ({} bytes)", vless_request.len());
        let mut state = self.state.lock().await;
        state.handshake_done = true;
        Ok(first_data.is_some())
    }

    pub async fn send_handshake_if_needed(&self) -> Result<bool> {
        self.ensure_handshake(None).await
    }

    pub async fn read(&self, buf: &mut [u8]) -> Result<usize> {
        {
            let mut state = self.state.lock().await;
            if !state.read_buffer.is_empty() {
                let len = std::cmp::min(buf.len(), state.read_buffer.len());
                buf[..len].copy_from_slice(&state.read_buffer.split_to(len));
                log::trace!("[VLESS] Read {} bytes from buffer (remaining: {})", len, state.read_buffer.len());
                return Ok(len);
            }
        }

        loop {
            let next_message = {
                let mut read_half = self.read_half.lock().await;
                read_half.next().await
            };

            match next_message {
                Some(Ok(Message::Binary(data))) => {
                    if data.is_empty() {
                        log::trace!("[VLESS] Received empty binary message, continuing");
                        continue;
                    }
                    log::debug!(
                        "[VLESS] Received binary frame len={} hex={}{}",
                        data.len(),
                        format_bytes_hex(&data[..data.len().min(32)]),
                        if data.len() > 32 { " ..." } else { "" },
                    );
                    let payload = {
                        let mut state = self.state.lock().await;
                        Self::consume_response_header(&mut state, &data)
                    };
                    let Some(payload) = payload else {
                        log::debug!("[VLESS] Response header still pending after len={}", data.len());
                        continue;
                    };
                    if payload.is_empty() {
                        log::debug!("[VLESS] Response header consumed, payload empty");
                        continue;
                    }
                    let len = std::cmp::min(buf.len(), payload.len());
                    buf[..len].copy_from_slice(&payload[..len]);
                    if payload.len() > len {
                        let mut state = self.state.lock().await;
                        state.read_buffer.extend_from_slice(&payload[len..]);
                    }
                    log::debug!("[VLESS] Read {} bytes from WebSocket payload (total: {})", len, payload.len());
                    return Ok(len);
                }
                Some(Ok(Message::Close(_))) => {
                    log::info!("[VLESS] Received close frame");
                    self.mark_remote_closed().await;
                    return Ok(0);
                }
                Some(Ok(Message::Ping(payload))) => {
                    log::trace!("[VLESS] Received ping ({} bytes), sending pong", payload.len());
                    let mut write_half = self.write_half.lock().await;
                    write_half.send(Message::Pong(payload)).await
                        .map_err(|e| {
                            log::error!("[VLESS] Pong send failed: {}", e);
                            Error::Network(format!("WebSocket pong failed: {}", e))
                        })?;
                    continue;
                }
                Some(Ok(Message::Pong(_))) => {
                    log::trace!("[VLESS] Received pong, continuing");
                    continue;
                }
                Some(Ok(other)) => {
                    log::debug!("[VLESS] Received other message type: {:?}", other);
                    continue;
                }
                Some(Err(e)) => {
                    log::error!("[VLESS] WebSocket error: {}", e);
                    self.mark_remote_closed().await;
                    return Err(Error::Network(format!("WebSocket error: {}", e)));
                }
                None => {
                    log::info!("[VLESS] WebSocket stream ended");
                    self.mark_remote_closed().await;
                    return Ok(0);
                }
            }
        }
    }

    pub async fn write(&self, buf: &[u8]) -> Result<()> {
        if self.is_remote_closed().await {
            return Err(Error::ConnectionClosed);
        }

        if self.ensure_handshake(Some(buf)).await? {
            log::info!("[VLESS] Auto-handshake on first write ({} bytes data)", buf.len());
            return Ok(());
        }

        let mut write_half = self.write_half.lock().await;
        write_half.send(Message::Binary(buf.to_vec())).await
            .map_err(|e| {
                if is_websocket_already_closed_error(&e.to_string()) {
                    return Error::ConnectionClosed;
                }
                log::error!("[VLESS] Write failed: {}", e);
                Error::Network(format!("WebSocket send failed: {}", e))
            })?;

        log::trace!("[VLESS] Wrote {} bytes", buf.len());
        Ok(())
    }

    pub async fn close(&self) -> Result<()> {
        log::info!("[VLESS] Closing stream");
        let mut write_half = self.write_half.lock().await;
        let _ = write_half.close().await;
        log::info!("[VLESS] Stream closed");
        Ok(())
    }

    pub fn local_bind_addr(&self) -> Option<SocketAddr> {
        self.local_bind_addr
    }
}

fn non_empty_str(value: Option<&str>) -> Option<&str> {
    value.and_then(|item| {
        let trimmed = item.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed)
        }
    })
}

async fn connect_tcp_with_fallback(server_addr: &str, server_port: u16) -> Result<TcpStream> {
    let mut candidates: Vec<SocketAddr> = lookup_host((server_addr, server_port))
        .await
        .map_err(|e| {
            log::error!("[VLESS] DNS lookup failed for {}:{}: {}", server_addr, server_port, e);
            Error::Network(format!("DNS lookup failed: {}", e))
        })?
        .collect();

    candidates.sort_by_key(|addr| if addr.is_ipv4() { 0 } else { 1 });

    if candidates.is_empty() {
        return Err(Error::Network(format!(
            "No resolved addresses for {}:{}",
            server_addr, server_port,
        )));
    }

    let mut last_error: Option<Error> = None;
    for candidate in candidates {
        log::debug!("[VLESS] Trying TCP connect to {}", candidate);
        match timeout(Duration::from_secs(10), TcpStream::connect(candidate)).await {
            Ok(Ok(socket)) => return Ok(socket),
            Ok(Err(e)) => {
                log::warn!("[VLESS] TCP connect failed for {}: {}", candidate, e);
                last_error = Some(Error::Network(format!("TCP connect failed for {}: {}", candidate, e)));
            }
            Err(_) => {
                log::warn!("[VLESS] TCP connect timed out for {}", candidate);
                last_error = Some(Error::Timeout);
            }
        }
    }

    Err(last_error.unwrap_or_else(|| Error::Network("TCP connect failed".to_string())))
}

fn is_websocket_already_closed_error(message: &str) -> bool {
    let message = message.to_ascii_lowercase();
    message.contains("sending after closing is not allowed")
        || message.contains("connection closed normally")
        || message.contains("already closed")
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
    buf.extend_from_slice(&[0x01]);
    buf.extend_from_slice(&[(port >> 8) as u8, (port & 0xFF) as u8]);

    if let Ok(ip) = addr.parse::<std::net::Ipv4Addr>() {
        buf.extend_from_slice(&[0x01]);
        buf.extend_from_slice(&ip.octets());
    } else if let Ok(ip) = addr.parse::<std::net::Ipv6Addr>() {
        buf.extend_from_slice(&[0x03]);
        buf.extend_from_slice(&ip.octets());
    } else {
        buf.extend_from_slice(&[0x02]);
        buf.extend_from_slice(&[addr.len() as u8]);
        buf.extend_from_slice(addr.as_bytes());
    }

    buf.freeze()
}

mod base64 {
    use base64::prelude::*;
    
    pub fn encode(input: &[u8]) -> String {
        BASE64_STANDARD.encode(input)
    }
}

fn format_bytes_hex(bytes: &[u8]) -> String {
    bytes
        .iter()
        .map(|byte| format!("{:02x}", byte))
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::{build_vless_request, parse_uuid};

    #[test]
    fn builds_expected_ipv4_request() {
        let uuid = parse_uuid("86c50e3a-5b87-49dd-bd20-03c7f2735e40").unwrap();
        let request = build_vless_request(&uuid, "192.168.1.76", 3002);
        assert_eq!(request.len(), 26);
        assert_eq!(request[0], 0x00);
        assert_eq!(request[17], 0x00);
        assert_eq!(request[18], 0x01);
        assert_eq!(request[19], 0x0b);
        assert_eq!(request[20], 0xba);
        assert_eq!(request[21], 0x01);
        assert_eq!(&request[22..26], &[192, 168, 1, 76]);
    }

    #[test]
    fn builds_expected_domain_request() {
        let uuid = parse_uuid("86c50e3a-5b87-49dd-bd20-03c7f2735e40").unwrap();
        let request = build_vless_request(&uuid, "www.google.com", 443);
        assert_eq!(request.len(), 37);
        assert_eq!(request[0], 0x00);
        assert_eq!(request[17], 0x00);
        assert_eq!(request[18], 0x01);
        assert_eq!(request[19], 0x01);
        assert_eq!(request[20], 0xbb);
        assert_eq!(request[21], 0x02);
        assert_eq!(request[22], 14);
        assert_eq!(&request[23..], b"www.google.com");
    }
}
