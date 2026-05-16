pub mod mux;

use crate::common::Result;

pub struct ConnectionPool {
    max_connections: usize,
}

impl ConnectionPool {
    pub fn new(max_connections: usize) -> Self {
        Self { max_connections }
    }
    
    pub async fn get_connection(&self, target: &str) -> Result<()> {
        log::debug!("Getting connection for {}", target);
        Ok(())
    }
}
