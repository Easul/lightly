use crate::common::Error;
use crate::common::Result;
use bytes::{Bytes, BytesMut};

pub const MAX_VLESS_RESPONSE_ADDONS_LENGTH: usize = 64;

pub struct VlessResponseDecodeState {
    pub response_header_pending: bool,
    pub response_header_buffer: BytesMut,
}

impl VlessResponseDecodeState {
    pub fn new() -> Self {
        Self {
            response_header_pending: true,
            response_header_buffer: BytesMut::new(),
        }
    }
}

pub fn parse_uuid(uuid_str: &str) -> Result<[u8; 16]> {
    let hex_str = uuid_str.replace("-", "");
    if hex_str.len() != 32 {
        return Err(Error::InvalidConfig("Invalid UUID format".to_string()));
    }

    let mut bytes = [0u8; 16];
    for i in 0..16 {
        bytes[i] = u8::from_str_radix(&hex_str[i * 2..i * 2 + 2], 16)
            .map_err(|_| Error::InvalidConfig("Invalid UUID hex".to_string()))?;
    }

    Ok(bytes)
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

pub fn consume_response_header(
    state: &mut VlessResponseDecodeState,
    chunk: &[u8],
) -> Option<Vec<u8>> {
    if !state.response_header_pending {
        return Some(chunk.to_vec());
    }

    state.response_header_buffer.extend_from_slice(chunk);
    if state.response_header_buffer.len() < 2 {
        return None;
    }

    if state.response_header_buffer[0] != 0x00 {
        let payload = state.response_header_buffer.split().to_vec();
        state.response_header_pending = false;
        return Some(payload);
    }

    let addons_length = state.response_header_buffer[1] as usize;
    if addons_length > MAX_VLESS_RESPONSE_ADDONS_LENGTH {
        let payload = state.response_header_buffer.split().to_vec();
        state.response_header_pending = false;
        return Some(payload);
    }

    let header_length = 2 + addons_length;
    if state.response_header_buffer.len() < header_length {
        return None;
    }

    let payload = state
        .response_header_buffer
        .split_off(header_length)
        .to_vec();
    state.response_header_buffer.clear();
    state.response_header_pending = false;
    Some(payload)
}

#[cfg(test)]
mod tests {
    use super::{
        build_vless_request, consume_response_header, parse_uuid, VlessResponseDecodeState,
        MAX_VLESS_RESPONSE_ADDONS_LENGTH,
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
