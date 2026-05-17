use crate::common::{Result, Error};
use bytes::BytesMut;
use std::net::SocketAddr;
use std::sync::Arc;
use sha2::{Sha256, Digest};
use tokio::sync::Mutex;
use quinn::{Endpoint, ClientConfig};
use quinn::crypto::rustls::QuicClientConfig;
use rustls::pki_types::ServerName;

pub struct Hysteria2Client {
    config: Hysteria2Config,
    endpoint: Arc<Mutex<Option<Endpoint>>>,
    connection: Arc<Mutex<Option<quinn::Connection>>>,
}

#[derive(Debug, Clone)]
pub struct Hysteria2Config {
    pub server_addr: String,
    pub server_port: u16,
    pub password: String,
    pub sni: Option<String>,
    pub obfs: Option<String>,
}

pub struct Hysteria2Stream {
    send: quinn::SendStream,
    recv: quinn::RecvStream,
    read_buffer: BytesMut,
}

impl Hysteria2Client {
    pub fn new(config: Hysteria2Config) -> Self {
        Self {
            config,
            endpoint: Arc::new(Mutex::new(None)),
            connection: Arc::new(Mutex::new(None)),
        }
    }

    pub async fn connect(&self, target_addr: &str, target_port: u16) -> Result<Hysteria2Stream> {
        let connection = self.get_or_create_connection().await?;
        
        let (mut send, recv) = connection
            .open_bi()
            .await
            .map_err(|e| Error::Network(format!("Failed to open QUIC stream: {}", e)))?;
        
        let auth_payload = build_auth_request(target_addr, target_port, &self.config.password);
        
        send.write_all(&auth_payload)
            .await
            .map_err(|e| Error::Network(format!("Failed to send Hysteria2 auth: {}", e)))?;
        
        if self.config.obfs.is_some() {
        }
        
        Ok(Hysteria2Stream {
            send,
            recv,
            read_buffer: BytesMut::new(),
        })
    }

    async fn get_or_create_connection(&self) -> Result<quinn::Connection> {
        let mut conn_lock = self.connection.lock().await;
        
        if let Some(connection) = conn_lock.as_ref() {
            if connection.close_reason().is_none() {
                return Ok(connection.clone());
            }
        }
        
        let server_addr = format!("{}:{}", self.config.server_addr, self.config.server_port)
            .parse::<SocketAddr>()
            .map_err(|e| Error::Network(format!("Invalid server address: {}", e)))?;
        
        let client_config = build_quinn_client_config(&self.config.sni)?;
        
        let bind_addr: SocketAddr = "0.0.0.0:0".parse().unwrap();
        
        let mut endpoint = Endpoint::client(bind_addr)
            .map_err(|e| Error::Network(format!("Failed to create QUIC endpoint: {}", e)))?;
        
        endpoint.set_default_client_config(client_config);
        
        let server_name = self.config.sni.clone()
            .unwrap_or_else(|| self.config.server_addr.clone());
        
        let connection = endpoint
            .connect(server_addr, &server_name)
            .map_err(|e| Error::Network(format!("Failed to create QUIC connection: {}", e)))?
            .await
            .map_err(|e| Error::Network(format!("QUIC handshake failed: {}", e)))?;
        
        *conn_lock = Some(connection.clone());
        
        let mut endpoint_lock = self.endpoint.lock().await;
        *endpoint_lock = Some(endpoint);
        
        Ok(connection)
    }
}

impl Hysteria2Stream {
    pub async fn read(&mut self, buf: &mut [u8]) -> Result<usize> {
        if !self.read_buffer.is_empty() {
            let len = std::cmp::min(buf.len(), self.read_buffer.len());
            buf[..len].copy_from_slice(&self.read_buffer.split_to(len));
            return Ok(len);
        }
        
        match self.recv.read(buf).await {
            Ok(Some(n)) => Ok(n),
            Ok(None) => Ok(0),
            Err(e) => Err(Error::Network(format!("Hysteria2 read error: {}", e))),
        }
    }

    pub async fn write(&mut self, buf: &[u8]) -> Result<()> {
        self.send
            .write_all(buf)
            .await
            .map_err(|e| Error::Network(format!("Hysteria2 write error: {}", e)))
    }

    pub async fn close(&mut self) -> Result<()> {
        let _ = self.send.finish();
        Ok(())
    }
}

fn build_quinn_client_config(_sni: &Option<String>) -> Result<ClientConfig> {
    let roots = rustls::RootCertStore::from_iter(
        webpki_roots::TLS_SERVER_ROOTS.iter().cloned()
    );
    
    let client_config = rustls::ClientConfig::builder()
        .with_root_certificates(roots)
        .with_no_client_auth();
    
    let quic_config = QuicClientConfig::try_from(client_config)
        .map_err(|e| Error::Network(format!("Invalid TLS config: {}", e)))?;
    
    Ok(ClientConfig::new(Arc::new(quic_config)))
}

fn generate_obfuscation_data(password: &str) -> Vec<u8> {
    use rand::Rng;
    
    let mut rng = rand::thread_rng();
    let size = rng.gen_range(32..128);
    let mut data = vec![0u8; size];
    rng.fill(&mut data[..]);
    
    let mut hasher = Sha256::new();
    hasher.update(password.as_bytes());
    hasher.update(&data);
    let hash = hasher.finalize();
    
    data.extend_from_slice(&hash[..8]);
    data
}

fn build_auth_request(target_addr: &str, target_port: u16, password: &str) -> Vec<u8> {
    let mut buf = BytesMut::new();
    
    buf.extend_from_slice(&[0x01]); 
    
    let auth = format!("{}:{}", target_addr, target_port);
    let auth_len = auth.len() as u8;
    buf.extend_from_slice(&[auth_len]);
    buf.extend_from_slice(auth.as_bytes());
    
    let mut hasher = Sha256::new();
    hasher.update(password.as_bytes());
    hasher.update(&[target_port as u8, (target_port >> 8) as u8]);
    hasher.update(target_addr.as_bytes());
    let hash = hasher.finalize();
    buf.extend_from_slice(&hash[..16]);
    
    buf.to_vec()
}
