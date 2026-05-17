#[cfg(feature = "mux-experimental")]
pub mod mux;

use crate::outbound::OutboundClient;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

pub struct OutboundClientRegistry {
    clients: Arc<Mutex<HashMap<String, Arc<dyn OutboundClient>>>>,
}

impl OutboundClientRegistry {
    pub fn new(_max_connections: usize) -> Self {
        Self {
            clients: Arc::new(Mutex::new(HashMap::new())),
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
}

pub type ConnectionPool = OutboundClientRegistry;
