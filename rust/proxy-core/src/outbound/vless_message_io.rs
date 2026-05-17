use crate::common::Error;
use crate::outbound::vless_stream_state::VlessStreamState;
use tokio_tungstenite::tungstenite::Message;

pub enum VlessReadAction {
    Continue,
    Return(usize),
    SendPong(Vec<u8>),
    MarkRemoteClosedAndReturn(usize),
    MarkRemoteClosedAndError(String),
    MarkRemoteClosedAndEof,
}

pub fn handle_read_message(
    message: Message,
    state: &mut VlessStreamState,
    buf: &mut [u8],
) -> VlessReadAction {
    match message {
        Message::Binary(data) => {
            if data.is_empty() {
                return VlessReadAction::Continue;
            }

            let payload = state.consume_frame_payload(&data, buf);
            match payload {
                None => VlessReadAction::Continue,
                Some(0) => VlessReadAction::Continue,
                Some(len) => VlessReadAction::Return(len),
            }
        }
        Message::Close(_) => {
            state.mark_remote_closed();
            if let Some(len) = state.take_buffered(buf) {
                VlessReadAction::MarkRemoteClosedAndReturn(len)
            } else {
                VlessReadAction::MarkRemoteClosedAndReturn(0)
            }
        }
        Message::Ping(payload) => VlessReadAction::SendPong(payload.to_vec()),
        Message::Pong(_) => VlessReadAction::Continue,
        other => {
            let _ = other;
            VlessReadAction::Continue
        }
    }
}

pub fn handle_read_error(error: &Error) -> VlessReadAction {
    VlessReadAction::MarkRemoteClosedAndError(format!("{}", error))
}

pub fn handle_stream_end() -> VlessReadAction {
    VlessReadAction::MarkRemoteClosedAndEof
}

#[cfg(test)]
mod tests {
    use super::{handle_read_message, VlessReadAction};
    use crate::outbound::vless_stream_state::VlessStreamState;
    use tokio_tungstenite::tungstenite::Message;

    #[test]
    fn binary_message_returns_payload_len_after_header_strip() {
        let mut state = VlessStreamState::new();
        let mut out = [0u8; 4];

        let action = handle_read_message(
            Message::Binary(vec![0x00, 0x00, 1, 2]),
            &mut state,
            &mut out,
        );

        match action {
            VlessReadAction::Return(len) => {
                assert_eq!(len, 2);
                assert_eq!(&out[..2], &[1, 2]);
            }
            _ => panic!("expected return action"),
        }
    }

    #[test]
    fn close_message_drains_buffered_bytes_before_eof() {
        let mut state = VlessStreamState::new();
        let mut tiny = [0u8; 1];
        let mut out = [0u8; 2];
        let _ = state.consume_frame_payload(&[0x00, 0x00, 9, 8], &mut tiny);

        let action = handle_read_message(Message::Close(None), &mut state, &mut out);

        match action {
            VlessReadAction::MarkRemoteClosedAndReturn(len) => {
                assert_eq!(len, 1);
                assert_eq!(&out[..1], &[8]);
            }
            _ => panic!("expected close drain action"),
        }
    }

    #[test]
    fn ping_message_requests_pong() {
        let mut state = VlessStreamState::new();
        let mut out = [0u8; 1];

        let action = handle_read_message(Message::Ping(vec![7, 8].into()), &mut state, &mut out);

        match action {
            VlessReadAction::SendPong(payload) => assert_eq!(payload, vec![7, 8]),
            _ => panic!("expected pong action"),
        }
    }
}
