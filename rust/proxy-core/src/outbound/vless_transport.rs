use crate::common::Error;
use crate::common::Result;
use crate::outbound::vless::{SecurityType, VlessConfig};
use http::Request;
use rustls_022::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls_022::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls_022::{ClientConfig, DigitallySignedStruct, RootCertStore, SignatureScheme};
use std::net::SocketAddr;
use tokio::net::{lookup_host, TcpStream};
use tokio::time::{timeout, Duration};

pub struct VlessConnectPlan {
    pub use_tls: bool,
    pub tls_server_name: String,
    pub ws_url: String,
    pub host_header: String,
}

pub fn build_connect_plan(config: &VlessConfig) -> VlessConnectPlan {
    let use_tls = config.security == SecurityType::Tls;
    let ws_host = non_empty_str(config.host.as_deref());
    let tls_server_name = non_empty_str(config.sni.as_deref())
        .or(ws_host)
        .unwrap_or(&config.server_addr);
    let request_uri_host = if use_tls {
        tls_server_name
    } else {
        &config.server_addr
    };
    let ws_url = format!(
        "{}://{}:{}{}",
        if use_tls { "wss" } else { "ws" },
        request_uri_host,
        config.server_port,
        config.path
    );

    let http_host = ws_host.unwrap_or(tls_server_name);
    let host_header = build_websocket_host_header(http_host, config.server_port, use_tls);

    VlessConnectPlan {
        use_tls,
        tls_server_name: tls_server_name.to_string(),
        ws_url,
        host_header,
    }
}

pub fn build_websocket_request(plan: &VlessConnectPlan) -> Result<Request<()>> {
    Request::builder()
        .uri(&plan.ws_url)
        .header("Host", &plan.host_header)
        .header("Upgrade", "websocket")
        .header("Connection", "Upgrade")
        .header("Sec-WebSocket-Key", generate_sec_websocket_key())
        .header("Sec-WebSocket-Version", "13")
        .body(())
        .map_err(|e| Error::InvalidConfig(format!("Invalid WebSocket request: {}", e)))
}

pub fn build_rustls_config(config: &VlessConfig) -> Result<std::sync::Arc<ClientConfig>> {
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

pub async fn connect_tcp_with_fallback(server_addr: &str, server_port: u16) -> Result<TcpStream> {
    let mut candidates: Vec<SocketAddr> = lookup_host((server_addr, server_port))
        .await
        .map_err(|e| {
            log::error!(
                "[VLESS] DNS lookup failed for {}:{}: {}",
                server_addr,
                server_port,
                e
            );
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
            Ok(Ok(socket)) => {
                let _ = socket.set_nodelay(true);
                return Ok(socket);
            }
            Ok(Err(e)) => {
                log::warn!("[VLESS] TCP connect failed for {}: {}", candidate, e);
                last_error = Some(Error::Network(format!(
                    "TCP connect failed for {}: {}",
                    candidate, e
                )));
            }
            Err(_) => {
                log::warn!("[VLESS] TCP connect timed out for {}", candidate);
                last_error = Some(Error::Timeout);
            }
        }
    }

    Err(last_error.unwrap_or_else(|| Error::Network("TCP connect failed".to_string())))
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

#[cfg(test)]
mod tests {
    use super::build_connect_plan;
    use crate::outbound::vless::{SecurityType, VlessConfig};

    fn base_config() -> VlessConfig {
        VlessConfig {
            uuid: "86c50e3a-5b87-49dd-bd20-03c7f2735e40".to_string(),
            server_addr: "edge.example.com".to_string(),
            server_port: 443,
            security: SecurityType::Tls,
            host: None,
            sni: None,
            path: "/ws".to_string(),
            tls_insecure: false,
        }
    }

    #[test]
    fn connect_plan_prefers_sni_for_tls_url_and_host_for_http_header() {
        let mut config = base_config();
        config.host = Some("cdn.example.com".to_string());
        config.sni = Some("tls.example.com".to_string());

        let plan = build_connect_plan(&config);

        assert!(plan.use_tls);
        assert_eq!(plan.tls_server_name, "tls.example.com");
        assert_eq!(plan.ws_url, "wss://tls.example.com:443/ws");
        assert_eq!(plan.host_header, "cdn.example.com");
    }

    #[test]
    fn connect_plan_uses_server_addr_for_non_tls_request_uri() {
        let mut config = base_config();
        config.security = SecurityType::None;
        config.host = Some("cdn.example.com".to_string());
        config.sni = Some("tls.example.com".to_string());
        config.server_port = 8080;

        let plan = build_connect_plan(&config);

        assert!(!plan.use_tls);
        assert_eq!(plan.tls_server_name, "tls.example.com");
        assert_eq!(plan.ws_url, "ws://edge.example.com:8080/ws");
        assert_eq!(plan.host_header, "cdn.example.com:8080");
    }
}
