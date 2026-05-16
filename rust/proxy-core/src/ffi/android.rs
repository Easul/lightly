use std::sync::Arc;
use tokio::runtime::Runtime;
use once_cell::sync::OnceCell;
use tokio::sync::Mutex;

use jni::objects::JString;
use jni::signature::JavaType;
use jni::sys::{jint, jlong};
use jni::JNIEnv;

use crate::inbound::InboundServer;
use crate::pool::ConnectionPool;

static RUNTIME: OnceCell<Runtime> = OnceCell::new();
static SERVER_HANDLE: OnceCell<Arc<Mutex<Option<tokio::task::JoinHandle<()>>>>> = OnceCell::new();

#[no_mangle]
pub extern "system" fn Java_com_proxy_core_ProxyCore_nativeInit(
    mut env: JNIEnv,
    _class: jni::objects::JClass,
    log_level: JString,
) -> jint {
    let level: String = match env.get_string(&log_level) {
        Ok(s) => s.into(),
        Err(_) => "info".to_string(),
    };
    
    android_logger::init_once(
        android_logger::Config::default()
            .with_max_level(log::LevelFilter::from_str(&level).unwrap_or(log::LevelFilter::Info)),
    );
    
    log::info!("Proxy core Android initialized");
    0
}

#[no_mangle]
pub extern "system" fn Java_com_proxy_core_ProxyCore_nativeStart(
    mut env: JNIEnv,
    _class: jni::objects::JClass,
    listen_addr: JString,
    config: JString,
) -> jint {
    let addr: String = match env.get_string(&listen_addr) {
        Ok(s) => s.into(),
        Err(_) => return -1,
    };
    
    let _config_json: String = match env.get_string(&config) {
        Ok(s) => s.into(),
        Err(_) => "{}".to_string(),
    };
    
    let rt = match RUNTIME.get_or_try_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(4)
            .enable_all()
            .build()
    }) {
        Ok(rt) => rt,
        Err(_) => return -2,
    };
    
    let handle = SERVER_HANDLE.get_or_init(|| Arc::new(Mutex::new(None)));
    
    let result = rt.block_on(async {
        let pool = Arc::new(ConnectionPool::new(100));
        
        match InboundServer::bind(&addr, pool).await {
            Ok(server) => {
                let server_task = tokio::spawn(async move {
                    if let Err(e) = server.run().await {
                        log::error!("Server error: {}", e);
                    }
                });
                
                *handle.lock().await = Some(server_task);
                0
            }
            Err(e) => {
                log::error!("Failed to bind server: {}", e);
                -3
            }
        }
    });
    
    result
}

#[no_mangle]
pub extern "system" fn Java_com_proxy_core_ProxyCore_nativeStop(
    _env: JNIEnv,
    _class: jni::objects::JClass,
) -> jint {
    if let Some(handle) = SERVER_HANDLE.get() {
        let rt = match RUNTIME.get() {
            Some(rt) => rt,
            None => return -1,
        };
        
        rt.block_on(async {
            let mut guard = handle.lock().await;
            if let Some(task) = guard.take() {
                task.abort();
                log::info!("Proxy server stopped");
            }
        });
    }
    
    0
}

use std::str::FromStr;
