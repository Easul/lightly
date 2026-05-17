use bytes::{Bytes, BytesMut};
use futures::{SinkExt, StreamExt};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::TcpStream;
use tokio::sync::{mpsc, Mutex, RwLock};
use tokio_tungstenite::{connect_async, tungstenite::Message, MaybeTlsStream, WebSocketStream};

use crate::common::{Error, Result};
use crate::outbound::vless::{build_vless_request, parse_uuid};

const MUX_FRAME_HEADER_LEN: usize = 8;
const MUX_CMD_DATA: u8 = 0x01;
const MUX_CMD_OPEN: u8 = 0x02;
const MUX_CMD_CLOSE: u8 = 0x03;

#[derive(Debug)]
pub struct MuxConnection {
    ws: Arc<Mutex<WebSocketStream<MaybeTlsStream<TcpStream>>>>,
    streams: Arc<RwLock<HashMap<u32, MuxStreamHandle>>>,
    next_stream_id: AtomicU32,
    recv_task: Arc<Mutex<Option<tokio::task::JoinHandle<()>>>>,
}

#[derive(Debug)]
struct MuxStreamHandle {
    tx: mpsc::UnboundedSender<Bytes>,
}

#[derive(Debug)]
pub struct MuxStream {
    stream_id: u32,
    conn: Arc<MuxConnection>,
    rx: mpsc::UnboundedReceiver<Bytes>,
    read_buffer: BytesMut,
    closed: bool,
}

impl MuxConnection {
    pub async fn connect(ws_url: &str, uuid: &str, host: &str) -> Result<Arc<Self>> {
        let request = http::Request::builder()
            .uri(ws_url)
            .header("Host", host)
            .header("Upgrade", "websocket")
            .header("Connection", "Upgrade")
            .header("Sec-WebSocket-Key", generate_sec_websocket_key())
            .header("Sec-WebSocket-Version", "13")
            .body(())
            .map_err(|e| Error::Network(e.to_string()))?;

        let (ws, _) = connect_async(request)
            .await
            .map_err(|e| Error::Network(format!("WebSocket connection failed: {}", e)))?;

        let conn = Arc::new(Self {
            ws: Arc::new(Mutex::new(ws)),
            streams: Arc::new(RwLock::new(HashMap::new())),
            next_stream_id: AtomicU32::new(1),
            recv_task: Arc::new(Mutex::new(None)),
        });

        let conn_clone = conn.clone();
        let recv_task = tokio::spawn(async move {
            conn_clone.run_receive_loop().await;
        });

        *conn.recv_task.lock().await = Some(recv_task);

        Ok(conn)
    }

    async fn run_receive_loop(&self) {
        loop {
            let msg = {
                let mut ws = self.ws.lock().await;
                match ws.next().await {
                    Some(Ok(msg)) => msg,
                    Some(Err(e)) => {
                        log::error!("WebSocket error: {}", e);
                        break;
                    }
                    None => {
                        log::debug!("WebSocket closed");
                        break;
                    }
                }
            };

            if let Message::Binary(data) = msg {
                if data.len() < MUX_FRAME_HEADER_LEN {
                    continue;
                }

                let stream_id = ((data[0] as u32) << 24)
                    | ((data[1] as u32) << 16)
                    | ((data[2] as u32) << 8)
                    | (data[3] as u32);
                let cmd = data[4];
                let payload = &data[MUX_FRAME_HEADER_LEN..];

                match cmd {
                    MUX_CMD_DATA => {
                        let streams = self.streams.read().await;
                        if let Some(handle) = streams.get(&stream_id) {
                            let _ = handle.tx.send(Bytes::copy_from_slice(payload));
                        }
                    }
                    MUX_CMD_CLOSE => {
                        self.remove_stream(stream_id).await;
                    }
                    _ => {}
                }
            }
        }

        let mut streams = self.streams.write().await;
        streams.clear();
    }

    pub async fn open_stream(&self, target_addr: &str, target_port: u16) -> Result<MuxStream> {
        let stream_id = self.next_stream_id.fetch_add(1, Ordering::SeqCst);

        let (tx, rx) = mpsc::unbounded_channel();

        {
            let mut streams = self.streams.write().await;
            streams.insert(stream_id, MuxStreamHandle { tx });
        }

        let vless_req = build_vless_request_bytes(&[0u8; 16], target_addr, target_port);

        let frame = build_mux_frame(stream_id, MUX_CMD_OPEN, &vless_req);

        {
            let mut ws = self.ws.lock().await;
            ws.send(Message::Binary(frame.to_vec()))
                .await
                .map_err(|e| Error::Network(format!("Failed to send open stream: {}", e)))?;
        }

        Ok(MuxStream {
            stream_id,
            conn: Arc::new(self.clone_for_stream()),
            rx,
            read_buffer: BytesMut::new(),
            closed: false,
        })
    }

    async fn send_data(&self, stream_id: u32, data: &[u8]) -> Result<()> {
        let frame = build_mux_frame(stream_id, MUX_CMD_DATA, data);

        let mut ws = self.ws.lock().await;
        ws.send(Message::Binary(frame.to_vec()))
            .await
            .map_err(|e| Error::Network(format!("Failed to send data: {}", e)))?;

        Ok(())
    }

    async fn close_stream(&self, stream_id: u32) -> Result<()> {
        let frame = build_mux_frame(stream_id, MUX_CMD_CLOSE, &[]);

        let mut ws = self.ws.lock().await;
        ws.send(Message::Binary(frame.to_vec()))
            .await
            .map_err(|e| Error::Network(format!("Failed to close stream: {}", e)))?;

        self.remove_stream(stream_id).await;
        Ok(())
    }

    async fn remove_stream(&self, stream_id: u32) {
        let mut streams = self.streams.write().await;
        streams.remove(&stream_id);
    }

    fn clone_for_stream(&self) -> Self {
        Self {
            ws: self.ws.clone(),
            streams: self.streams.clone(),
            next_stream_id: AtomicU32::new(self.next_stream_id.load(Ordering::SeqCst)),
            recv_task: self.recv_task.clone(),
        }
    }
}

impl MuxStream {
    pub async fn read(&mut self, buf: &mut [u8]) -> Result<usize> {
        if self.closed {
            return Ok(0);
        }

        if !self.read_buffer.is_empty() {
            let len = std::cmp::min(buf.len(), self.read_buffer.len());
            buf[..len].copy_from_slice(&self.read_buffer.split_to(len));
            return Ok(len);
        }

        match self.rx.recv().await {
            Some(data) => {
                let len = std::cmp::min(buf.len(), data.len());
                buf[..len].copy_from_slice(&data[..len]);
                if data.len() > len {
                    self.read_buffer.extend_from_slice(&data[len..]);
                }
                Ok(len)
            }
            None => {
                self.closed = true;
                Ok(0)
            }
        }
    }

    pub async fn write(&mut self, buf: &[u8]) -> Result<()> {
        if self.closed {
            return Err(Error::ConnectionClosed);
        }

        self.conn.send_data(self.stream_id, buf).await
    }

    pub async fn close(&mut self) -> Result<()> {
        if self.closed {
            return Ok(());
        }

        self.closed = true;
        self.conn.close_stream(self.stream_id).await
    }
}

fn build_mux_frame(stream_id: u32, cmd: u8, payload: &[u8]) -> Bytes {
    let mut frame = BytesMut::with_capacity(MUX_FRAME_HEADER_LEN + payload.len());

    frame.extend_from_slice(&[
        (stream_id >> 24) as u8,
        (stream_id >> 16) as u8,
        (stream_id >> 8) as u8,
        stream_id as u8,
    ]);
    frame.extend_from_slice(&[cmd, 0, 0, 0]);
    frame.extend_from_slice(payload);

    frame.freeze()
}

fn build_vless_request_bytes(uuid: &[u8; 16], addr: &str, port: u16) -> Bytes {
    build_vless_request(uuid, addr, port)
}

fn generate_sec_websocket_key() -> String {
    use rand::Rng;
    let mut bytes = [0u8; 16];
    rand::thread_rng().fill(&mut bytes);
    base64::encode(&bytes)
}

mod base64 {
    use base64::prelude::*;

    pub fn encode(input: &[u8]) -> String {
        BASE64_STANDARD.encode(input)
    }
}
