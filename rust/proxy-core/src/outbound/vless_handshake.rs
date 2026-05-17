use bytes::Bytes;

use crate::outbound::vless_codec::build_vless_request;

pub struct PreparedVlessHandshake {
    pub payload: Bytes,
    pub request_len: usize,
    pub first_payload_len: usize,
}

pub fn prepare_vless_handshake(
    uuid: &[u8; 16],
    target_addr: &str,
    target_port: u16,
    first_data: Option<&[u8]>,
) -> PreparedVlessHandshake {
    let request = build_vless_request(uuid, target_addr, target_port);
    let request_len = request.len();
    let first_payload_len = first_data.map(|data| data.len()).unwrap_or(0);

    let payload = if let Some(data) = first_data {
        let mut combined = Vec::with_capacity(request_len + data.len());
        combined.extend_from_slice(&request);
        combined.extend_from_slice(data);
        Bytes::from(combined)
    } else {
        request
    };

    PreparedVlessHandshake {
        payload,
        request_len,
        first_payload_len,
    }
}

#[cfg(test)]
mod tests {
    use super::prepare_vless_handshake;

    #[test]
    fn prepares_handshake_without_first_payload() {
        let uuid = [0x11; 16];
        let handshake = prepare_vless_handshake(&uuid, "example.com", 443, None);

        assert_eq!(handshake.request_len, handshake.payload.len());
        assert_eq!(handshake.first_payload_len, 0);
        assert_eq!(handshake.payload[0], 0x00);
        assert_eq!(handshake.payload[17], 0x00);
    }

    #[test]
    fn prepares_handshake_with_coalesced_first_payload() {
        let uuid = [0x22; 16];
        let handshake = prepare_vless_handshake(&uuid, "example.com", 443, Some(&[1, 2, 3]));

        assert_eq!(handshake.first_payload_len, 3);
        assert_eq!(handshake.payload.len(), handshake.request_len + 3);
        assert_eq!(&handshake.payload[handshake.request_len..], &[1, 2, 3]);
    }
}
