use crate::outbound::vless_codec::{consume_response_header, VlessResponseDecodeState};
use bytes::BytesMut;

pub struct VlessStreamState {
    read_buffer: BytesMut,
    pub handshake_done: bool,
    response_state: VlessResponseDecodeState,
    remote_closed: bool,
}

impl VlessStreamState {
    pub fn new() -> Self {
        Self {
            read_buffer: BytesMut::new(),
            handshake_done: false,
            response_state: VlessResponseDecodeState::new(),
            remote_closed: false,
        }
    }

    pub fn mark_remote_closed(&mut self) {
        self.remote_closed = true;
    }

    pub fn is_remote_closed(&self) -> bool {
        self.remote_closed
    }

    pub fn take_buffered(&mut self, buf: &mut [u8]) -> Option<usize> {
        if self.read_buffer.is_empty() {
            return None;
        }

        let len = std::cmp::min(buf.len(), self.read_buffer.len());
        buf[..len].copy_from_slice(&self.read_buffer.split_to(len));
        Some(len)
    }

    pub fn remaining_buffer_len(&self) -> usize {
        self.read_buffer.len()
    }

    pub fn consume_frame_payload(&mut self, chunk: &[u8], buf: &mut [u8]) -> Option<usize> {
        let payload = consume_response_header(&mut self.response_state, chunk)?;
        if payload.is_empty() {
            return Some(0);
        }

        let len = std::cmp::min(buf.len(), payload.len());
        buf[..len].copy_from_slice(&payload[..len]);
        if payload.len() > len {
            self.read_buffer.extend_from_slice(&payload[len..]);
        }
        Some(len)
    }
}

#[cfg(test)]
mod tests {
    use super::VlessStreamState;

    #[test]
    fn take_buffered_drains_incrementally() {
        let mut state = VlessStreamState::new();
        let mut first = [0u8; 2];
        let mut second = [0u8; 2];

        let mut scratch = [0u8; 2];
        let _ = state.consume_frame_payload(&[0x00, 0x00, 1, 2, 3, 4], &mut scratch);

        let len1 = state.take_buffered(&mut first).unwrap();
        let len2 = state.take_buffered(&mut second);

        assert_eq!(len1, 2);
        assert_eq!(&first, &[3, 4]);
        assert_eq!(len2, None);
    }

    #[test]
    fn consume_frame_payload_buffers_tail_when_output_buffer_is_small() {
        let mut state = VlessStreamState::new();
        let mut out = [0u8; 2];

        let len = state
            .consume_frame_payload(&[0x00, 0x00, 0xaa, 0xbb, 0xcc], &mut out)
            .unwrap();

        assert_eq!(len, 2);
        assert_eq!(&out, &[0xaa, 0xbb]);
        assert_eq!(state.remaining_buffer_len(), 1);
    }

    #[test]
    fn consume_frame_payload_returns_zero_for_header_only_frame() {
        let mut state = VlessStreamState::new();
        let mut out = [0u8; 4];

        let len = state
            .consume_frame_payload(&[0x00, 0x00], &mut out)
            .unwrap();

        assert_eq!(len, 0);
        assert_eq!(state.remaining_buffer_len(), 0);
    }
}
