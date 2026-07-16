use crate::common::Result;
use crate::inbound::relay;
use crate::outbound::OutboundClient;
use std::net::{IpAddr, SocketAddr};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::time::{sleep, timeout, Duration};

const AUTH_NONE: u8 = 0x00;
const AUTH_USERNAME_PASSWORD: u8 = 0x02;
const AUTH_NO_ACCEPTABLE: u8 = 0xFF;

pub async fn handle_socks5(
    mut stream: TcpStream,
    outbound: Option<Arc<dyn OutboundClient>>,
) -> Result<()> {
    let _ = stream.set_nodelay(true);
    let peer_addr = stream
        .peer_addr()
        .unwrap_or_else(|_| "unknown".parse().unwrap());
    log::info!("[SOCKS5] New connection from {}", peer_addr);

    let mut buf = [0u8; 2];
    stream.read_exact(&mut buf).await?;
    log::debug!("[SOCKS5] Version: {}, Methods count: {}", buf[0], buf[1]);

    if buf[0] != 0x05 {
        log::warn!("[SOCKS5] Invalid SOCKS version: {}", buf[0]);
        return Err(crate::common::Error::Protocol(
            "Invalid SOCKS version".to_string(),
        ));
    }

    let nmethods = buf[1] as usize;
    let mut methods = vec![0u8; nmethods];
    stream.read_exact(&mut methods).await?;
    log::debug!("[SOCKS5] Client offered auth methods: {:?}", methods);

    let selected_auth = if let Some(method) = select_auth_method(&methods) {
        match method {
            AUTH_USERNAME_PASSWORD => {
                log::debug!("[SOCKS5] Selecting USERNAME/PASSWORD (0x02)");
            }
            AUTH_NONE => {
                log::debug!("[SOCKS5] Selecting NO AUTH (0x00)");
            }
            _ => {}
        }
        method
    } else {
        log::warn!("[SOCKS5] No acceptable auth method from client");
        stream.write_all(&[0x05, AUTH_NO_ACCEPTABLE]).await?;
        return Err(crate::common::Error::Protocol(
            "No supported authentication method".to_string(),
        ));
    };

    stream.write_all(&[0x05, selected_auth]).await?;

    if selected_auth == AUTH_USERNAME_PASSWORD {
        let mut auth_ver = [0u8; 1];
        stream.read_exact(&mut auth_ver).await?;
        log::debug!("[SOCKS5] Auth version: {}", auth_ver[0]);
        if auth_ver[0] != 0x01 {
            stream.write_all(&[0x01, 0x01]).await?;
            return Err(crate::common::Error::Protocol(
                "Invalid auth version".to_string(),
            ));
        }

        let mut ulen = [0u8; 1];
        stream.read_exact(&mut ulen).await?;
        let mut username = vec![0u8; ulen[0] as usize];
        stream.read_exact(&mut username).await?;

        let mut plen = [0u8; 1];
        stream.read_exact(&mut plen).await?;
        let mut password = vec![0u8; plen[0] as usize];
        stream.read_exact(&mut password).await?;

        log::debug!(
            "[SOCKS5] Auth credentials received ({} bytes user, {} bytes pass)",
            ulen[0],
            plen[0]
        );
        stream.write_all(&[0x01, 0x00]).await?;
    }

    let mut request = [0u8; 4];
    stream.read_exact(&mut request).await?;
    log::debug!(
        "[SOCKS5] Request: ver={}, cmd={}, atyp={}",
        request[0],
        request[1],
        request[3]
    );

    if request[0] != 0x05 || request[1] != 0x01 {
        log::warn!(
            "[SOCKS5] Invalid request: ver={}, cmd={}",
            request[0],
            request[1]
        );
        stream
            .write_all(&[0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
            .await?;
        return Err(crate::common::Error::Protocol(
            "Invalid SOCKS request".to_string(),
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
            let mut addr = [0u8; 16];
            stream.read_exact(&mut addr).await?;
            let segments = addr
                .chunks_exact(2)
                .map(|chunk| format!("{:x}", u16::from_be_bytes([chunk[0], chunk[1]])))
                .collect::<Vec<_>>();
            segments.join(":")
        }
        _ => {
            return Err(crate::common::Error::Protocol(
                "Invalid address type".to_string(),
            ));
        }
    };

    let mut port = [0u8; 2];
    stream.read_exact(&mut port).await?;
    let port = ((port[0] as u16) << 8) | (port[1] as u16);

    log::info!("[SOCKS5] {} → Connecting to {}:{}", peer_addr, addr, port);

    match outbound {
        Some(client) => match client.connect(&addr, port).await {
            Ok(outbound_stream) => {
                let bind_addr = resolve_reply_bind_addr(
                    outbound_stream.local_bind_addr(),
                    stream.local_addr().ok(),
                );
                let reply = build_connect_success_reply(bind_addr);
                stream.write_all(&reply).await?;
                stream.flush().await?;
                log::info!("[SOCKS5] Reply bind {}", bind_addr);

                let initial_payload = read_initial_payload_after_connect_reply(
                    &mut stream,
                    Duration::from_millis(250),
                )
                .await?;

                let initial_payload_len = initial_payload.as_ref().map_or(0, Vec::len);
                let first_downstream_grace = outbound_stream.first_downstream_grace();
                outbound_stream
                    .write(initial_payload.as_deref().unwrap_or(&[]))
                    .await?;
                if initial_payload_len > 0 {
                    log::info!(
                        "[SOCKS5] Primed outbound with {} client bytes; delaying downstream {}ms",
                        initial_payload_len,
                        first_downstream_grace.as_millis(),
                    );
                    sleep(first_downstream_grace).await;
                }

                let outbound_upload = outbound_stream.clone();
                let outbound_download = outbound_stream.clone();
                let cleanup_outbound = outbound_stream.clone();
                let client_input_done = Arc::new(AtomicBool::new(false));
                let client_input_done_for_c2v = client_input_done.clone();
                let client_input_done_for_v2c = client_input_done.clone();

                let (client_r, client_w) = stream.split();

                log::info!("[SOCKS5] {} ↔ Starting bidirectional relay", peer_addr);

                let c2v = relay::relay_client_to_vless(
                    client_r,
                    outbound_upload,
                    8192,
                    None,
                    None,
                    false,
                    |n| {
                        log::trace!("[SOCKS5] Client → VLESS: {} bytes", n);
                    },
                    |_| {},
                    |error| {
                        log::warn!(
                            "[SOCKS5] Handshake fallback failed before first payload: {}",
                            error
                        );
                    },
                    |error, _| {
                        log::warn!("[SOCKS5] Client → VLESS: Write failed: {}", error);
                    },
                    |total| {
                        client_input_done_for_c2v.store(true, Ordering::Relaxed);
                        log::info!("[SOCKS5] Client → VLESS: EOF (total {} bytes)", total);
                    },
                    |error, _| {
                        client_input_done_for_c2v.store(true, Ordering::Relaxed);
                        if is_expected_client_read_close(error) {
                            log::info!("[SOCKS5] Client → VLESS: Peer closed input ({})", error);
                        } else {
                            log::warn!("[SOCKS5] Client → VLESS: Read error {}", error);
                        }
                    },
                    |total| {
                        log::debug!("[SOCKS5] Client → VLESS: Closed (total {} bytes)", total);
                    },
                );

                let client_input_done_for_v2c_write = client_input_done_for_v2c.clone();
                let client_input_done_for_v2c_read = client_input_done_for_v2c.clone();
                let v2c = relay::relay_vless_downstream_to_client(
                    outbound_download,
                    client_w,
                    8192,
                    |n| {
                        log::trace!("[SOCKS5] VLESS → Client: {} bytes", n);
                    },
                    |total| {
                        log::info!("[SOCKS5] VLESS → Client: EOF (total {} bytes)", total);
                    },
                    move |error, _| {
                        if is_expected_client_write_close(error) {
                            let saw_client_eof =
                                client_input_done_for_v2c_write.swap(true, Ordering::Relaxed);
                            if saw_client_eof {
                                log::debug!(
                                    "[SOCKS5] VLESS → Client: Peer already closed after client EOF ({})",
                                    error,
                                );
                            } else {
                                log::info!(
                                    "[SOCKS5] VLESS → Client: Peer closed receive side ({})",
                                    error,
                                );
                            }
                        } else {
                            log::warn!("[SOCKS5] VLESS → Client: Write failed: {}", error);
                        }
                    },
                    move |error, _| {
                        if client_input_done_for_v2c_read.load(Ordering::Relaxed) {
                            log::debug!(
                                "[SOCKS5] VLESS → Client: Read error after client EOF ({})",
                                error
                            );
                        } else {
                            log::warn!("[SOCKS5] VLESS → Client: Read error {}", error);
                        }
                    },
                    |total| {
                        log::debug!("[SOCKS5] VLESS → Client: Closed (total {} bytes)", total);
                    },
                );

                relay::run_vless_relay_session(c2v, v2c, std::future::ready(()), cleanup_outbound)
                    .await;
                log::info!("[SOCKS5] {} ↔ Bidirectional relay completed", peer_addr);
            }
            Err(e) => {
                log::error!("[SOCKS5] VLESS connection failed: {}", e);
                stream
                    .write_all(&[0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                    .await?;
            }
        },
        None => match TcpStream::connect(format!("{}:{}", addr, port)).await {
            Ok(mut target) => {
                let bind_addr =
                    resolve_reply_bind_addr(target.local_addr().ok(), stream.local_addr().ok());
                let reply = build_connect_success_reply(bind_addr);
                stream.write_all(&reply).await?;
                stream.flush().await?;

                if let Some(initial_payload) = read_initial_payload_after_connect_reply(
                    &mut stream,
                    Duration::from_millis(250),
                )
                .await?
                {
                    target.write_all(&initial_payload).await?;
                    sleep(Duration::from_millis(100)).await;
                }

                relay::pipe_bidirectional(stream, target, "SOCKS5").await;
            }
            Err(e) => {
                stream
                    .write_all(&[0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                    .await?;
                return Err(e.into());
            }
        },
    }

    Ok(())
}

async fn read_initial_payload_after_connect_reply<R>(
    reader: &mut R,
    wait: Duration,
) -> std::io::Result<Option<Vec<u8>>>
where
    R: tokio::io::AsyncRead + Unpin,
{
    let mut buffer = vec![0u8; 8192];
    match timeout(wait, reader.read(&mut buffer)).await {
        Ok(Ok(0)) | Err(_) => Ok(None),
        Ok(Ok(read)) => {
            buffer.truncate(read);
            Ok(Some(buffer))
        }
        Ok(Err(error)) => Err(error),
    }
}

fn select_auth_method(methods: &[u8]) -> Option<u8> {
    if methods.contains(&AUTH_NONE) {
        return Some(AUTH_NONE);
    }
    if methods.contains(&AUTH_USERNAME_PASSWORD) {
        return Some(AUTH_USERNAME_PASSWORD);
    }
    None
}

fn resolve_reply_bind_addr(
    outbound_local_addr: Option<SocketAddr>,
    client_local_addr: Option<SocketAddr>,
) -> SocketAddr {
    if let Some(addr) = outbound_local_addr {
        if addr.port() != 0 && !addr.ip().is_unspecified() {
            return addr;
        }
    }

    if let Some(addr) = client_local_addr {
        let ip = if addr.ip().is_unspecified() {
            loopback_for_ip(addr.ip())
        } else {
            addr.ip()
        };
        let port = if addr.port() == 0 { 1 } else { addr.port() };
        return SocketAddr::new(ip, port);
    }

    SocketAddr::from(([127, 0, 0, 1], 1))
}

fn build_connect_success_reply(bind_addr: SocketAddr) -> Vec<u8> {
    let mut reply = Vec::with_capacity(match bind_addr.ip() {
        IpAddr::V4(_) => 10,
        IpAddr::V6(_) => 22,
    });
    reply.extend_from_slice(&[0x05, 0x00, 0x00]);
    match bind_addr.ip() {
        IpAddr::V4(ipv4) => {
            reply.push(0x01);
            reply.extend_from_slice(&ipv4.octets());
        }
        IpAddr::V6(ipv6) => {
            reply.push(0x04);
            reply.extend_from_slice(&ipv6.octets());
        }
    }
    reply.extend_from_slice(&bind_addr.port().to_be_bytes());
    reply
}

fn loopback_for_ip(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V4(_) => IpAddr::V4(std::net::Ipv4Addr::LOCALHOST),
        IpAddr::V6(_) => IpAddr::V6(std::net::Ipv6Addr::LOCALHOST),
    }
}

fn is_expected_client_read_close(error: &std::io::Error) -> bool {
    matches!(
        error.kind(),
        std::io::ErrorKind::ConnectionReset
            | std::io::ErrorKind::ConnectionAborted
            | std::io::ErrorKind::UnexpectedEof
            | std::io::ErrorKind::TimedOut
    )
}

fn is_expected_client_write_close(error: &std::io::Error) -> bool {
    matches!(
        error.kind(),
        std::io::ErrorKind::BrokenPipe
            | std::io::ErrorKind::ConnectionReset
            | std::io::ErrorKind::ConnectionAborted
            | std::io::ErrorKind::NotConnected
    )
}

#[cfg(test)]
mod tests {
    use super::{
        build_connect_success_reply, is_expected_client_read_close, is_expected_client_write_close,
        resolve_reply_bind_addr, select_auth_method, AUTH_NONE, AUTH_USERNAME_PASSWORD,
    };
    use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};
    use tokio::io::AsyncWriteExt;
    use tokio::time::Duration;

    #[test]
    fn prefers_no_auth_when_both_methods_are_offered() {
        assert_eq!(
            select_auth_method(&[AUTH_NONE, AUTH_USERNAME_PASSWORD]),
            Some(AUTH_NONE),
        );
    }

    #[tokio::test]
    async fn buffers_client_payload_before_starting_downstream_relay() {
        let (mut server, mut client) = tokio::io::duplex(64);
        let read = tokio::spawn(async move {
            super::read_initial_payload_after_connect_reply(&mut server, Duration::from_millis(100))
                .await
                .unwrap()
        });

        client.write_all(b"telegram-first-payload").await.unwrap();

        assert_eq!(
            read.await.unwrap(),
            Some(b"telegram-first-payload".to_vec())
        );
    }

    #[tokio::test]
    async fn allows_server_first_protocol_after_boundary_timeout() {
        let (mut server, _client) = tokio::io::duplex(64);

        let payload =
            super::read_initial_payload_after_connect_reply(&mut server, Duration::from_millis(1))
                .await
                .unwrap();

        assert!(payload.is_none());
    }

    #[test]
    fn falls_back_to_no_auth_when_username_password_is_absent() {
        assert_eq!(select_auth_method(&[AUTH_NONE]), Some(AUTH_NONE));
    }

    #[test]
    fn keeps_real_outbound_bind_addr_when_available() {
        let addr = SocketAddr::from(([192, 168, 2, 101], 48872));
        assert_eq!(resolve_reply_bind_addr(Some(addr), None), addr);
    }

    #[test]
    fn falls_back_to_client_local_addr_without_zero_values() {
        let resolved = resolve_reply_bind_addr(
            Some(SocketAddr::from(([0, 0, 0, 0], 0))),
            Some(SocketAddr::from(([0, 0, 0, 0], 1080))),
        );

        assert_eq!(resolved.ip(), IpAddr::V4(Ipv4Addr::LOCALHOST));
        assert_eq!(resolved.port(), 1080);
    }

    #[test]
    fn builds_complete_ipv4_connect_reply_as_one_buffer() {
        let reply = build_connect_success_reply(SocketAddr::from(([192, 168, 0, 145], 39027)));

        assert_eq!(
            reply,
            vec![0x05, 0x00, 0x00, 0x01, 192, 168, 0, 145, 0x98, 0x73]
        );
    }

    #[test]
    fn builds_complete_ipv6_connect_reply_as_one_buffer() {
        let addr = SocketAddr::new(IpAddr::V6(Ipv6Addr::LOCALHOST), 23333);
        let reply = build_connect_success_reply(addr);

        assert_eq!(reply.len(), 22);
        assert_eq!(&reply[..4], &[0x05, 0x00, 0x00, 0x04]);
        assert_eq!(&reply[4..20], &Ipv6Addr::LOCALHOST.octets());
        assert_eq!(&reply[20..], &23333u16.to_be_bytes());
    }

    #[test]
    fn treats_client_write_close_errors_as_expected() {
        for kind in [
            std::io::ErrorKind::BrokenPipe,
            std::io::ErrorKind::ConnectionReset,
            std::io::ErrorKind::ConnectionAborted,
            std::io::ErrorKind::NotConnected,
        ] {
            let error = std::io::Error::new(kind, "telegram closed client socket");
            assert!(is_expected_client_write_close(&error));
        }
    }

    #[test]
    fn keeps_unrelated_client_write_errors_unexpected() {
        let error = std::io::Error::new(std::io::ErrorKind::TimedOut, "write timed out");
        assert!(!is_expected_client_write_close(&error));
    }

    #[test]
    fn treats_client_read_timeout_as_expected_close() {
        let error = std::io::Error::new(std::io::ErrorKind::TimedOut, "read timed out");
        assert!(is_expected_client_read_close(&error));
    }
}
