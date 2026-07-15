use crate::common::{Error, Result};
use crate::outbound::{OutboundClient, ProxyStream};
use async_trait::async_trait;
use bytes::{Bytes, BytesMut};
use quinn::crypto::rustls::QuicClientConfig;
use quinn::{ClientConfig, Endpoint, TokioRuntime, TransportConfig};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, SignatureScheme};
use std::net::{IpAddr, SocketAddr};
use std::sync::Arc;
use std::time::Duration;
use tokio::io::AsyncReadExt;
use tokio::net::lookup_host;
use tokio::sync::Mutex;

pub struct Hysteria2Client {
    config: Hysteria2Config,
    endpoint: Arc<Mutex<Option<Endpoint>>>,
    connection: Arc<Mutex<Option<quinn::Connection>>>,
    h3_sender: Arc<Mutex<Option<h3::client::SendRequest<h3_quinn::OpenStreams, Bytes>>>>,
    h3_driver: Arc<Mutex<Option<tokio::task::JoinHandle<()>>>>,
}

#[derive(Debug, Clone)]
pub struct Hysteria2Config {
    pub server_addr: String,
    pub server_port: u16,
    pub password: String,
    pub sni: Option<String>,
    pub obfs: Option<String>,
    pub obfs_password: Option<String>,
    pub tls_insecure: bool,
}

pub struct Hysteria2Stream {
    send: Mutex<quinn::SendStream>,
    recv: Mutex<quinn::RecvStream>,
    local_bind_addr: Option<SocketAddr>,
}

const HYSTERIA2_FIRST_DOWNSTREAM_GRACE: Duration = Duration::from_millis(350);

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
    ) -> std::result::Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, rustls::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, rustls::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        vec![
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
        ]
    }
}

impl Hysteria2Client {
    pub fn new(config: Hysteria2Config) -> Self {
        Self {
            config,
            endpoint: Arc::new(Mutex::new(None)),
            connection: Arc::new(Mutex::new(None)),
            h3_sender: Arc::new(Mutex::new(None)),
            h3_driver: Arc::new(Mutex::new(None)),
        }
    }

    pub async fn connect(&self, target_addr: &str, target_port: u16) -> Result<Hysteria2Stream> {
        let connection = self.get_or_create_connection().await?;
        let endpoint_addr = self
            .endpoint
            .lock()
            .await
            .as_ref()
            .and_then(|endpoint| endpoint.local_addr().ok());
        let local_bind_addr =
            resolve_hysteria_local_bind_addr(connection.local_ip(), endpoint_addr);

        let (mut send, mut recv) = connection
            .open_bi()
            .await
            .map_err(|e| Error::Network(format!("Failed to open QUIC stream: {}", e)))?;

        let request_payload = build_tcp_request(target_addr, target_port);

        send.write_all(&request_payload)
            .await
            .map_err(|e| Error::Network(format!("Failed to send Hysteria2 TCP request: {}", e)))?;

        read_tcp_response(&mut recv).await?;

        Ok(Hysteria2Stream {
            send: Mutex::new(send),
            recv: Mutex::new(recv),
            local_bind_addr,
        })
    }

    async fn get_or_create_connection(&self) -> Result<quinn::Connection> {
        let mut conn_lock = self.connection.lock().await;

        if let Some(connection) = conn_lock.as_ref() {
            if connection.close_reason().is_none() {
                return Ok(connection.clone());
            }
        }

        let server_addr =
            resolve_server_addr(&self.config.server_addr, self.config.server_port).await?;

        let client_config = build_quinn_client_config(&self.config.sni, self.config.tls_insecure)?;

        // Try binding to 0.0.0.0:0 first, fall back to 127.0.0.1:0 on Android
        // Some Android configurations reject binding to 0.0.0.0 (quinn#1624)
        let socket = match std::net::UdpSocket::bind("0.0.0.0:0") {
            Ok(s) => {
                log::debug!("Hysteria2 UDP socket bound to 0.0.0.0:0");
                s
            }
            Err(e) => {
                log::warn!(
                    "Hysteria2 bind 0.0.0.0:0 failed ({}), trying 127.0.0.1:0",
                    e
                );
                std::net::UdpSocket::bind("127.0.0.1:0").map_err(|e2| {
                    Error::Network(format!(
                        "Failed to bind UDP socket (0.0.0.0:0 → {}, 127.0.0.1:0 → {})",
                        e, e2
                    ))
                })?
            }
        };

        let mut endpoint = Endpoint::new(
            quinn::EndpointConfig::default(),
            None,
            socket,
            Arc::new(TokioRuntime),
        )
        .map_err(|e| Error::Network(format!("Failed to create QUIC endpoint: {}", e)))?;

        endpoint.set_default_client_config(client_config);

        let server_name = self
            .config
            .sni
            .clone()
            .unwrap_or_else(|| self.config.server_addr.clone());

        let connection = endpoint
            .connect(server_addr, &server_name)
            .map_err(|e| Error::Network(format!("Failed to create QUIC connection: {}", e)))?
            .await
            .map_err(|e| Error::Network(format!("QUIC handshake failed: {}", e)))?;

        let (sender, driver_handle) = authenticate_hysteria2(
            &connection,
            &self.config.password,
            &self.config.obfs,
            &self.config.obfs_password,
        )
        .await?;

        *conn_lock = Some(connection.clone());
        *self.h3_sender.lock().await = Some(sender);
        *self.h3_driver.lock().await = Some(driver_handle);

        let mut endpoint_lock = self.endpoint.lock().await;
        *endpoint_lock = Some(endpoint);

        Ok(connection)
    }
}

async fn resolve_server_addr(host: &str, port: u16) -> Result<SocketAddr> {
    if let Ok(addr) = format!("{}:{}", host, port).parse::<SocketAddr>() {
        return Ok(addr);
    }

    let mut addrs = lookup_host((host, port))
        .await
        .map_err(|e| Error::Network(format!("Failed to resolve Hysteria2 server: {}", e)))?;

    addrs.next().ok_or_else(|| {
        Error::Network(format!(
            "No address resolved for Hysteria2 server: {}",
            host
        ))
    })
}

async fn authenticate_hysteria2(
    connection: &quinn::Connection,
    password: &str,
    obfs: &Option<String>,
    obfs_password: &Option<String>,
) -> Result<(
    h3::client::SendRequest<h3_quinn::OpenStreams, Bytes>,
    tokio::task::JoinHandle<()>,
)> {
    let h3_connection = h3_quinn::Connection::new(connection.clone());
    let (mut driver, mut sender) = h3::client::builder()
        .build::<_, _, Bytes>(h3_connection)
        .await
        .map_err(|e| Error::Network(format!("Hysteria2 HTTP/3 setup failed: {}", e)))?;

    let driver_handle = tokio::spawn(async move {
        let _ = driver.wait_idle().await;
        log::debug!("Hysteria2 h3 driver ended");
    });

    let mut request_builder = http::Request::post("https://hysteria/auth")
        .header("Hysteria-Auth", password)
        .header("Hysteria-CC-RX", "0")
        .header("Hysteria-Padding", random_padding_string(64, 512));

    if let Some(obfs_type) = obfs {
        request_builder = request_builder.header("Hysteria-Obfs", obfs_type);
    }
    if let Some(obfs_pwd) = obfs_password {
        request_builder = request_builder.header("Hysteria-Obfs-Password", obfs_pwd);
    }

    let request = request_builder
        .body(())
        .map_err(|e| Error::Network(format!("Hysteria2 auth request build failed: {}", e)))?;

    let mut stream = sender
        .send_request(request)
        .await
        .map_err(|e| Error::Network(format!("Hysteria2 auth request failed: {}", e)))?;
    stream
        .finish()
        .await
        .map_err(|e| Error::Network(format!("Hysteria2 auth finish failed: {}", e)))?;

    let response = stream
        .recv_response()
        .await
        .map_err(|e| Error::Network(format!("Hysteria2 auth response failed: {}", e)))?;

    if response.status().as_u16() != 233 {
        return Err(Error::Network(format!(
            "Hysteria2 auth failed with status {}",
            response.status()
        )));
    }

    Ok((sender, driver_handle))
}

#[async_trait]
impl OutboundClient for Hysteria2Client {
    async fn connect(&self, addr: &str, port: u16) -> Result<Arc<dyn ProxyStream>> {
        Ok(Arc::new(Hysteria2Client::connect(self, addr, port).await?))
    }
}

impl Hysteria2Stream {
    pub async fn read(&self, buf: &mut [u8]) -> Result<usize> {
        let mut recv = self.recv.lock().await;
        match recv.read(buf).await {
            Ok(Some(n)) => Ok(n),
            Ok(None) => Ok(0),
            Err(e) => Err(Error::Network(format!("Hysteria2 read error: {}", e))),
        }
    }

    pub async fn write(&self, buf: &[u8]) -> Result<()> {
        let mut send = self.send.lock().await;
        send.write_all(buf)
            .await
            .map_err(|e| Error::Network(format!("Hysteria2 write error: {}", e)))
    }

    pub async fn close(&self) -> Result<()> {
        let mut send = self.send.lock().await;
        let _ = send.finish();
        Ok(())
    }
}

#[async_trait]
impl ProxyStream for Hysteria2Stream {
    async fn read(&self, buf: &mut [u8]) -> Result<usize> {
        Hysteria2Stream::read(self, buf).await
    }

    async fn write(&self, buf: &[u8]) -> Result<()> {
        Hysteria2Stream::write(self, buf).await
    }

    async fn close(&self) -> Result<()> {
        Hysteria2Stream::close(self).await
    }

    fn local_bind_addr(&self) -> Option<SocketAddr> {
        self.local_bind_addr
    }

    fn first_downstream_grace(&self) -> Duration {
        HYSTERIA2_FIRST_DOWNSTREAM_GRACE
    }
}

fn resolve_hysteria_local_bind_addr(
    connection_ip: Option<IpAddr>,
    endpoint_addr: Option<SocketAddr>,
) -> Option<SocketAddr> {
    endpoint_addr.map(|endpoint_addr| {
        let ip = connection_ip
            .filter(|ip| !ip.is_unspecified())
            .unwrap_or_else(|| match endpoint_addr.ip() {
                IpAddr::V4(_) => IpAddr::V4(std::net::Ipv4Addr::LOCALHOST),
                IpAddr::V6(_) => IpAddr::V6(std::net::Ipv6Addr::LOCALHOST),
            });
        SocketAddr::new(ip, endpoint_addr.port().max(1))
    })
}

fn build_quinn_client_config(_sni: &Option<String>, tls_insecure: bool) -> Result<ClientConfig> {
    let roots = rustls::RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());

    let mut client_config = rustls::ClientConfig::builder()
        .with_root_certificates(roots)
        .with_no_client_auth();
    client_config.alpn_protocols = vec![b"h3".to_vec()];

    if tls_insecure {
        client_config
            .dangerous()
            .set_certificate_verifier(Arc::new(NoCertificateVerification));
    }

    let quic_config = QuicClientConfig::try_from(client_config)
        .map_err(|e| Error::Network(format!("Invalid TLS config: {}", e)))?;

    let mut transport = TransportConfig::default();
    transport.max_idle_timeout(Some(
        Duration::from_secs(30)
            .try_into()
            .map_err(|e| Error::Network(format!("Invalid idle timeout: {}", e)))?,
    ));
    transport.keep_alive_interval(Some(Duration::from_secs(10)));

    let mut config = ClientConfig::new(Arc::new(quic_config));
    config.transport_config(Arc::new(transport));

    Ok(config)
}

fn random_padding_string(min_len: usize, max_len: usize) -> String {
    use rand::Rng;

    let mut rng = rand::thread_rng();
    let len = rng.gen_range(min_len..=max_len);
    const CHARS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    (0..len)
        .map(|_| CHARS[rng.gen_range(0..CHARS.len())] as char)
        .collect()
}

fn build_tcp_request(target_addr: &str, target_port: u16) -> Vec<u8> {
    let mut buf = BytesMut::new();
    let addr = format_tcp_target(target_addr, target_port);
    let padding = random_padding_string(64, 512).into_bytes();

    encode_quic_varint(0x401, &mut buf);
    encode_quic_varint(addr.len() as u64, &mut buf);
    buf.extend_from_slice(addr.as_bytes());
    encode_quic_varint(padding.len() as u64, &mut buf);
    buf.extend_from_slice(&padding);

    buf.to_vec()
}

fn format_tcp_target(target_addr: &str, target_port: u16) -> String {
    match target_addr.parse::<IpAddr>() {
        Ok(IpAddr::V6(addr)) => format!("[{}]:{}", addr, target_port),
        _ => format!("{}:{}", target_addr, target_port),
    }
}

async fn read_tcp_response(recv: &mut quinn::RecvStream) -> Result<()> {
    let status = recv
        .read_u8()
        .await
        .map_err(|e| Error::Network(format!("Hysteria2 TCP response status failed: {}", e)))?;
    let message_len = decode_quic_varint(recv).await? as usize;
    let mut message = vec![0u8; message_len];
    if message_len > 0 {
        recv.read_exact(&mut message)
            .await
            .map_err(|e| Error::Network(format!("Hysteria2 TCP response message failed: {}", e)))?;
    }
    let padding_len = decode_quic_varint(recv).await? as usize;
    if padding_len > 0 {
        let mut padding = vec![0u8; padding_len];
        recv.read_exact(&mut padding)
            .await
            .map_err(|e| Error::Network(format!("Hysteria2 TCP response padding failed: {}", e)))?;
    }

    if status != 0 {
        let text = String::from_utf8_lossy(&message);
        return Err(Error::Network(format!(
            "Hysteria2 TCP request failed: {}",
            text
        )));
    }

    Ok(())
}

fn encode_quic_varint(value: u64, buf: &mut BytesMut) {
    if value < (1 << 6) {
        buf.extend_from_slice(&[value as u8]);
    } else if value < (1 << 14) {
        let encoded = (value as u16) | 0x4000;
        buf.extend_from_slice(&encoded.to_be_bytes());
    } else if value < (1 << 30) {
        let encoded = (value as u32) | 0x8000_0000;
        buf.extend_from_slice(&encoded.to_be_bytes());
    } else {
        let encoded = value | 0xC000_0000_0000_0000;
        buf.extend_from_slice(&encoded.to_be_bytes());
    }
}

async fn decode_quic_varint(recv: &mut quinn::RecvStream) -> Result<u64> {
    let first = recv
        .read_u8()
        .await
        .map_err(|e| Error::Network(format!("Hysteria2 varint read failed: {}", e)))?;
    let tag = first >> 6;
    let mut value = (first & 0x3f) as u64;
    let extra = match tag {
        0 => 0,
        1 => 1,
        2 => 3,
        _ => 7,
    };
    for _ in 0..extra {
        let byte = recv
            .read_u8()
            .await
            .map_err(|e| Error::Network(format!("Hysteria2 varint read failed: {}", e)))?;
        value = (value << 8) | byte as u64;
    }
    Ok(value)
}

#[cfg(test)]
mod tests {
    use super::{
        format_tcp_target, resolve_hysteria_local_bind_addr, HYSTERIA2_FIRST_DOWNSTREAM_GRACE,
    };
    use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};
    use std::time::Duration;

    #[test]
    fn formats_ipv6_tcp_target_with_brackets() {
        assert_eq!(
            format_tcp_target("2001:67c:4e8:f002:0:0:0:a", 443),
            "[2001:67c:4e8:f002::a]:443"
        );
    }

    #[test]
    fn preserves_ipv4_and_domain_tcp_target_format() {
        assert_eq!(
            format_tcp_target("149.154.167.50", 443),
            "149.154.167.50:443"
        );
        assert_eq!(format_tcp_target("example.com", 443), "example.com:443");
    }

    #[test]
    fn uses_quic_route_ip_and_endpoint_port_for_socks_reply() {
        let endpoint = SocketAddr::from(([0, 0, 0, 0], 43210));
        let route_ip = IpAddr::V4(Ipv4Addr::new(192, 0, 2, 8));

        assert_eq!(
            resolve_hysteria_local_bind_addr(Some(route_ip), Some(endpoint)),
            Some(SocketAddr::new(route_ip, 43210))
        );
    }

    #[test]
    fn uses_concrete_loopback_when_quic_route_ip_is_unavailable() {
        assert_eq!(
            resolve_hysteria_local_bind_addr(
                None,
                Some(SocketAddr::new(IpAddr::V6(Ipv6Addr::UNSPECIFIED), 45678)),
            ),
            Some(SocketAddr::new(IpAddr::V6(Ipv6Addr::LOCALHOST), 45678))
        );
    }

    #[test]
    fn keeps_hysteria_first_downstream_grace_longer_than_default() {
        assert_eq!(HYSTERIA2_FIRST_DOWNSTREAM_GRACE, Duration::from_millis(350));
    }
}
