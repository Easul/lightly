use crate::common::Result;

pub struct MuxConnection {
    session_id: u32,
}

impl MuxConnection {
    pub fn new(session_id: u32) -> Self {
        Self { session_id }
    }
    
    pub async fn open_stream(&self, target: &str) -> Result<u32> {
        log::debug!("Opening stream {} to {}", self.session_id, target);
        Ok(0)
    }
}
