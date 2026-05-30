use crate::common::Error;
use crate::outbound::ProxyStream;
use std::future::Future;
use std::sync::Arc;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::time::{sleep, Duration};

pub async fn pipe_bidirectional(
    mut client: TcpStream,
    mut target: TcpStream,
    protocol_label: &str,
) {
    let (mut client_r, mut client_w) = client.split();
    let (mut target_r, mut target_w) = target.split();

    let c2t = tokio::io::copy(&mut client_r, &mut target_w);
    let t2c = tokio::io::copy(&mut target_r, &mut client_w);

    match tokio::try_join!(c2t, t2c) {
        Ok((c2t_bytes, t2c_bytes)) => {
            log::debug!(
                "{} tunnel closed: {} bytes client→target, {} bytes target→client",
                protocol_label,
                c2t_bytes,
                t2c_bytes
            );
        }
        Err(e) => {
            log::debug!("{} tunnel error: {}", protocol_label, e);
        }
    }
}

pub async fn relay_vless_downstream_to_client<
    W,
    OnChunk,
    OnEof,
    OnWriteError,
    OnReadError,
    OnClose,
>(
    outbound_download: Arc<dyn ProxyStream>,
    mut client_w: W,
    buffer_size: usize,
    mut on_chunk: OnChunk,
    mut on_eof: OnEof,
    mut on_write_error: OnWriteError,
    mut on_read_error: OnReadError,
    mut on_close: OnClose,
) where
    W: AsyncWrite + Unpin,
    OnChunk: FnMut(usize),
    OnEof: FnMut(usize),
    OnWriteError: FnMut(&std::io::Error, usize),
    OnReadError: FnMut(&Error, usize),
    OnClose: FnMut(usize),
{
    let mut buf = vec![0u8; buffer_size];
    let mut total = 0usize;

    loop {
        match outbound_download.read(&mut buf).await {
            Ok(0) => {
                on_eof(total);
                break;
            }
            Ok(n) => {
                total += n;
                on_chunk(n);
                if let Err(error) = client_w.write_all(&buf[..n]).await {
                    on_write_error(&error, total);
                    break;
                }
            }
            Err(error) => {
                on_read_error(&error, total);
                break;
            }
        }
    }

    let _ = client_w.shutdown().await;
    on_close(total);
}

pub async fn relay_client_to_vless<
    R,
    OnChunk,
    OnBufferedWriteError,
    OnFallbackWriteError,
    OnWriteError,
    OnEof,
    OnReadError,
    OnClose,
>(
    mut client_r: R,
    outbound_upload: Arc<dyn ProxyStream>,
    buffer_size: usize,
    initial_payload: Option<Vec<u8>>,
    first_payload_fallback_after: Option<Duration>,
    close_outbound_on_input_end: bool,
    mut on_chunk: OnChunk,
    mut on_buffered_write_error: OnBufferedWriteError,
    mut on_fallback_write_error: OnFallbackWriteError,
    mut on_write_error: OnWriteError,
    mut on_eof: OnEof,
    mut on_read_error: OnReadError,
    mut on_close: OnClose,
) where
    R: AsyncRead + Unpin,
    OnChunk: FnMut(usize),
    OnBufferedWriteError: FnMut(&Error),
    OnFallbackWriteError: FnMut(&Error),
    OnWriteError: FnMut(&Error, usize),
    OnEof: FnMut(usize),
    OnReadError: FnMut(&std::io::Error, usize),
    OnClose: FnMut(usize),
{
    let mut total = 0usize;
    let mut buf = vec![0u8; buffer_size];

    if let Some(initial_payload) = initial_payload.filter(|payload| !payload.is_empty()) {
        if let Err(error) = outbound_upload.write(&initial_payload).await {
            on_buffered_write_error(&error);
            on_close(total);
            return;
        }
    }

    let mut waiting_for_first_payload = first_payload_fallback_after.is_some();

    loop {
        let read_result = if let Some(delay) =
            first_payload_fallback_after.filter(|_| waiting_for_first_payload)
        {
            tokio::select! {
                result = client_r.read(&mut buf) => result,
                _ = sleep(delay) => {
                    if let Err(error) = outbound_upload.write(&[]).await {
                        if !matches!(error, Error::ConnectionClosed) {
                            on_fallback_write_error(&error);
                        }
                        break;
                    }
                    waiting_for_first_payload = false;
                    continue;
                }
            }
        } else {
            client_r.read(&mut buf).await
        };

        waiting_for_first_payload = false;

        match read_result {
            Ok(0) => {
                on_eof(total);
                if close_outbound_on_input_end {
                    let _ = outbound_upload.close().await;
                }
                break;
            }
            Ok(n) => {
                total += n;
                on_chunk(n);
                if let Err(error) = outbound_upload.write(&buf[..n]).await {
                    if !matches!(error, Error::ConnectionClosed) {
                        on_write_error(&error, total);
                    }
                    break;
                }
            }
            Err(error) => {
                on_read_error(&error, total);
                if close_outbound_on_input_end {
                    let _ = outbound_upload.close().await;
                }
                break;
            }
        }
    }

    on_close(total);
}

pub async fn run_vless_relay_session<C2V, V2C, PostJoin>(
    c2v: C2V,
    v2c: V2C,
    post_join: PostJoin,
    cleanup_outbound: Arc<dyn ProxyStream>,
) where
    C2V: Future<Output = ()>,
    V2C: Future<Output = ()>,
    PostJoin: Future<Output = ()>,
{
    tokio::join!(c2v, v2c);
    post_join.await;
    let _ = cleanup_outbound.close().await;
}
