pub mod mux;

use crate::common::Result;
use crate::outbound::OutboundClient;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

pub struct ConnectionPool {
    clients: Arc<Mutex<HashMap<String, Arc<dyn OutboundClient>>>>,
    max_connections: usize,
}

impl ConnectionPool {
    pub fn new(max_connections: usize) -> Self {
        Self {
            clients: Arc::new(Mutex::new(HashMap::new())),
            max_connections,
        }
    }

    pub async fn register_client(&self, name: String, client: Arc<dyn OutboundClient>) {
        let mut clients = self.clients.lock().await;
        clients.insert(name, client);
    }

    pub async fn get_client(&self, name: &str) -> Option<Arc<dyn OutboundClient>> {
        let clients = self.clients.lock().await;
        clients.get(name).cloned()
    }

    pub async fn get_connection(&self, _target: &str) -> Result<()> {
        log::debug!("Getting connection for {}", _target);
        Ok(())
    }
}
