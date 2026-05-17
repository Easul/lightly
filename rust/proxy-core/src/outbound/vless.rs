use crate::common::Error;
use crate::common::Result;
use crate::outbound::{OutboundClient, ProxyStream};
#[cfg(feature = "mux-experimental")]
pub use crate::outbound::vless_codec::{build_vless_request, parse_uuid};
use crate::outbound::vless_codec::parse_uuid;
use crate::outbound::vless_handshake::prepare_vless_handshake;
use crate::outbound::vless_message_io::{
    handle_read_error, handle_read_message, handle_stream_end, VlessReadAction,
};
use crate::outbound::vless_stream_state::VlessStreamState;
use crate::outbound::vless_transport::{
    build_connect_plan, build_rustls_config, build_websocket_request,
    connect_tcp_with_fallback,
};
use async_trait::async_trait;
use futures::{
    stream::{SplitSink, SplitStream},
    SinkExt, StreamExt,
};
use std::net::SocketAddr;
use tokio::net::TcpStream;
use tokio::sync::Mutex;
use tokio::time::{timeout, Duration};
use tokio_tungstenite::{client_async_tls_with_config, tungstenite::Message, Connector, MaybeTlsStream, WebSocketStream};

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

use std::sync::Arc;

impl VlessClient {
    pub fn new(config: VlessConfig) -> Self {
        Self { config }
    }

    pub async fn connect(&self, target_addr: &str, target_port: u16) -> Result<VlessStream> {
        log::info!(
            "[VLESS] Connecting to target {}:{}",
            target_addr,
            target_port
        );
        log::info!(
            "[VLESS] Server: {}:{}",
            self.config.server_addr,
            self.config.server_port
        );

        let uuid_bytes = parse_uuid(&self.config.uuid)?;
        log::debug!("[VLESS] UUID parsed successfully");

        let connect_plan = build_connect_plan(&self.config);
        log::info!("[VLESS] WebSocket URL: {}", connect_plan.ws_url);
        log::debug!("[VLESS] Host header: {}", connect_plan.host_header);
        log::debug!("[VLESS] TLS server name: {}", connect_plan.tls_server_name);

        let request = build_websocket_request(&connect_plan)?;

        let tcp_addr = format!("{}:{}", self.config.server_addr, self.config.server_port);
        log::info!(
            "[VLESS] Initiating WebSocket connection over TCP {}...",
            tcp_addr
        );
        let socket =
            connect_tcp_with_fallback(&self.config.server_addr, self.config.server_port).await?;
        let local_bind_addr = socket.local_addr().ok();

        let connector = if connect_plan.use_tls {
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
            state: Mutex::new(VlessStreamState::new()),
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

#[async_trait]
impl OutboundClient for VlessClient {
    async fn connect(&self, addr: &str, port: u16) -> Result<Arc<dyn ProxyStream>> {
        Ok(Arc::new(VlessClient::connect(self, addr, port).await?))
    }
}

impl VlessStream {
    async fn mark_remote_closed(&self) {
        let mut state = self.state.lock().await;
        state.mark_remote_closed();
    }

    async fn is_remote_closed(&self) -> bool {
        let state = self.state.lock().await;
        state.is_remote_closed()
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

        log::info!(
            "[VLESS] Performing handshake to {}:{} (first_data: {})",
            self.target_addr,
            self.target_port,
            first_data.map(|d| d.len()).unwrap_or(0)
        );

        let handshake = prepare_vless_handshake(
            &self.uuid,
            &self.target_addr,
            self.target_port,
            first_data,
        );
        log::debug!(
            "[VLESS] Request bytes len={} hex={}",
            handshake.payload.len(),
            format_bytes_hex(&handshake.payload),
        );

        if handshake.first_payload_len > 0 {
            log::debug!(
                "[VLESS] Combined handshake + first data: total={} request={} payload={}",
                handshake.payload.len(),
                handshake.request_len,
                handshake.first_payload_len,
            );
        }

        let mut write_half = self.write_half.lock().await;
        write_half
            .send(Message::Binary(handshake.payload.to_vec()))
            .await
            .map_err(|e| {
                log::error!("[VLESS] Handshake send failed: {}", e);
                Error::Network(format!("WebSocket send failed: {}", e))
            })?;

        log::info!(
            "[VLESS] Handshake sent successfully ({} bytes)",
            handshake.payload.len()
        );
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
            if let Some(len) = state.take_buffered(buf) {
                log::trace!(
                    "[VLESS] Read {} bytes from buffer (remaining: {})",
                    len,
                    state.remaining_buffer_len()
                );
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
                    log::debug!(
                        "[VLESS] Received binary frame len={} hex={}{}",
                        data.len(),
                        format_bytes_hex(&data[..data.len().min(32)]),
                        if data.len() > 32 { " ..." } else { "" },
                    );
                    let action = {
                        let mut state = self.state.lock().await;
                        handle_read_message(Message::Binary(data), &mut state, buf)
                    };
                    match action {
                        VlessReadAction::Continue => continue,
                        VlessReadAction::Return(len) => return Ok(len),
                        _ => continue,
                    }
                }
                Some(Ok(Message::Close(frame))) => {
                    log::info!("[VLESS] Received close frame");
                    let action = {
                        let mut state = self.state.lock().await;
                        handle_read_message(Message::Close(frame), &mut state, buf)
                    };
                    match action {
                        VlessReadAction::MarkRemoteClosedAndReturn(len) => {
                            return Ok(len);
                        }
                        _ => {
                            self.mark_remote_closed().await;
                            return Ok(0);
                        }
                    }
                }
                Some(Ok(Message::Ping(payload))) => {
                    let pong_payload = {
                        let mut state = self.state.lock().await;
                        match handle_read_message(Message::Ping(payload), &mut state, buf) {
                            VlessReadAction::SendPong(payload) => payload,
                            _ => continue,
                        }
                    };
                    let mut write_half = self.write_half.lock().await;
                    write_half.send(Message::Pong(pong_payload.into())).await.map_err(|e| {
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
                    {
                        let mut state = self.state.lock().await;
                        let _ = handle_read_message(other, &mut state, buf);
                    }
                    continue;
                }
                Some(Err(e)) => {
                    log::error!("[VLESS] WebSocket error: {}", e);
                    match handle_read_error(&Error::Network(format!("WebSocket error: {}", e))) {
                        VlessReadAction::MarkRemoteClosedAndError(message) => {
                            self.mark_remote_closed().await;
                            return Err(Error::Network(message));
                        }
                        _ => unreachable!(),
                    }
                }
                None => {
                    log::info!("[VLESS] WebSocket stream ended");
                    match handle_stream_end() {
                        VlessReadAction::MarkRemoteClosedAndEof => {
                            self.mark_remote_closed().await;
                            return Ok(0);
                        }
                        _ => unreachable!(),
                    }
                }
            }
        }
    }

    pub async fn write(&self, buf: &[u8]) -> Result<()> {
        if self.is_remote_closed().await {
            return Err(Error::ConnectionClosed);
        }

        if self.ensure_handshake(Some(buf)).await? {
            log::info!(
                "[VLESS] Auto-handshake on first write ({} bytes data)",
                buf.len()
            );
            return Ok(());
        }

        let mut write_half = self.write_half.lock().await;
        write_half
            .send(Message::Binary(buf.to_vec()))
            .await
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

#[async_trait]
impl ProxyStream for VlessStream {
    async fn read(&self, buf: &mut [u8]) -> Result<usize> {
        VlessStream::read(self, buf).await
    }

    async fn write(&self, buf: &[u8]) -> Result<()> {
        VlessStream::write(self, buf).await
    }

    async fn close(&self) -> Result<()> {
        VlessStream::close(self).await
    }

    fn local_bind_addr(&self) -> Option<SocketAddr> {
        VlessStream::local_bind_addr(self)
    }
}

fn is_websocket_already_closed_error(message: &str) -> bool {
    let message = message.to_ascii_lowercase();
    message.contains("sending after closing is not allowed")
        || message.contains("connection closed normally")
        || message.contains("already closed")
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
    use crate::outbound::vless_codec::{build_vless_request, parse_uuid};
    use crate::outbound::vless_codec::{
        consume_response_header, VlessResponseDecodeState, MAX_VLESS_RESPONSE_ADDONS_LENGTH,
    };

    fn response_state() -> VlessResponseDecodeState {
        VlessResponseDecodeState::new()
    }

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

    #[test]
    fn keeps_payload_when_first_byte_is_not_vless_version() {
        let mut state = response_state();
        let payload = [0xaf, 0xed, 0xaa, 0x0f];

        let result = consume_response_header(&mut state, &payload);

        assert_eq!(result, Some(payload.to_vec()));
        assert!(!state.response_header_pending);
        assert!(state.response_header_buffer.is_empty());
    }

    #[test]
    fn keeps_payload_when_addons_length_is_unreasonably_large() {
        let mut state = response_state();
        let payload = [
            0x00,
            (MAX_VLESS_RESPONSE_ADDONS_LENGTH as u8) + 1,
            0x12,
            0x34,
        ];

        let result = consume_response_header(&mut state, &payload);

        assert_eq!(result, Some(payload.to_vec()));
        assert!(!state.response_header_pending);
        assert!(state.response_header_buffer.is_empty());
    }

    #[test]
    fn strips_valid_vless_response_header_only() {
        let mut state = response_state();
        let payload = [0x00, 0x00, 0xde, 0xad, 0xbe, 0xef];

        let result = consume_response_header(&mut state, &payload);

        assert_eq!(result, Some(vec![0xde, 0xad, 0xbe, 0xef]));
        assert!(!state.response_header_pending);
        assert!(state.response_header_buffer.is_empty());
    }
}
