use once_cell::sync::OnceCell;
use std::sync::Arc;
use tokio::runtime::Runtime;
use tokio::sync::Mutex;

use jni::objects::JString;
use jni::signature::JavaType;
use jni::sys::{jint, jlong};
use jni::JNIEnv;

use crate::inbound::InboundServer;
use crate::outbound::hysteria2::{Hysteria2Client, Hysteria2Config};
use crate::outbound::vless::{SecurityType, VlessClient, VlessConfig};
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
        Err(_) => "debug".to_string(),
    };

    let _ = rustls::crypto::ring::default_provider().install_default();

    android_logger::init_once(
        android_logger::Config::default()
            .with_max_level(log::LevelFilter::Debug)
            .with_tag("ProxyCore"),
    );

    std::panic::set_hook(Box::new(|info| {
        let location = info.location().map(|l| format!("{}:{}:{}", l.file(), l.line(), l.column()))
            .unwrap_or_else(|| "unknown location".to_string());
        let payload = if let Some(s) = info.payload().downcast_ref::<&str>() {
            s.to_string()
        } else if let Some(s) = info.payload().downcast_ref::<String>() {
            s.clone()
        } else {
            "unknown panic payload".to_string()
        };
        log::error!("PANIC at {}: {}", location, payload);
    }));

    log::info!(
        "RustProxy: Proxy core Android initialized with log level: {}",
        level
    );
    log::debug!("RustProxy: Debug logging enabled");
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

    let config_json: String = match env.get_string(&config) {
        Ok(s) => s.into(),
        Err(_) => "{}".to_string(),
    };

    log::info!(
        "RustProxy: nativeStart called with addr={}, config={}",
        addr,
        config_json
    );

    let rt = match RUNTIME.get_or_try_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(4)
            .enable_all()
            .build()
    }) {
        Ok(rt) => rt,
        Err(e) => {
            log::error!("Failed to create Tokio runtime: {}", e);
            return -2;
        }
    };

    let handle = SERVER_HANDLE.get_or_init(|| Arc::new(Mutex::new(None)));

    let result = rt.block_on(async {
        let pool = Arc::new(ConnectionPool::new(100));

        if !config_json.is_empty() && config_json != "{}" {
            match parse_proxy_config(&config_json) {
                Ok(ProxyConfig::Vless(vless_config)) => {
                    log::info!(
                        "Registering VLESS client: {}:{}",
                        vless_config.server_addr,
                        vless_config.server_port
                    );
                    let client = VlessClient::new(vless_config);
                    pool.register_client("default".to_string(), Arc::new(client))
                        .await;
                    log::info!("VLESS client registered successfully");
                }
                Ok(ProxyConfig::Hysteria2(hysteria2_config)) => {
                    log::info!(
                        "Registering Hysteria2 client: {}:{}",
                        hysteria2_config.server_addr,
                        hysteria2_config.server_port
                    );
                    let client = Hysteria2Client::new(hysteria2_config);
                    pool.register_client("default".to_string(), Arc::new(client))
                        .await;
                    log::info!("Hysteria2 client registered successfully");
                }
                Err(e) => {
                    log::error!("Failed to parse proxy config: {}", e);
                    return -4;
                }
            }
        } else {
            log::info!("No proxy config provided, running in direct mode");
        }

        match InboundServer::bind(&addr, pool).await {
            Ok(server) => {
                log::info!("Server bound to {}, starting accept loop", addr);
                let server_task = tokio::spawn(async move {
                    if let Err(e) = server.run().await {
                        log::error!("Server error: {}", e);
                    }
                });

                *handle.lock().await = Some(server_task);
                log::info!("Server started successfully");
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

enum ProxyConfig {
    Vless(VlessConfig),
    Hysteria2(Hysteria2Config),
}

fn parse_proxy_config(json_str: &str) -> crate::common::Result<ProxyConfig> {
    use serde_json::Value;

    let value: Value = serde_json::from_str(json_str)
        .map_err(|e| crate::common::Error::InvalidConfig(format!("JSON parse error: {}", e)))?;

    if value.get("hysteria2").is_some() {
        return parse_hysteria2_config(json_str).map(ProxyConfig::Hysteria2);
    }

    parse_vless_config(json_str).map(ProxyConfig::Vless)
}

fn parse_vless_config(json_str: &str) -> crate::common::Result<VlessConfig> {
    use serde::Deserialize;

    #[derive(Deserialize)]
    struct OuterConfig {
        vless: InnerConfig,
    }

    #[derive(Deserialize)]
    struct InnerConfig {
        uuid: String,
        server_addr: String,
        server_port: u16,
        security: Option<String>,
        host: Option<String>,
        sni: Option<String>,
        path: Option<String>,
        tls_insecure: Option<bool>,
    }

    let outer: OuterConfig = serde_json::from_str(json_str)
        .map_err(|e| crate::common::Error::InvalidConfig(format!("JSON parse error: {}", e)))?;

    let security = match outer.vless.security.as_deref() {
        Some("tls") | None => SecurityType::Tls,
        Some("none") => SecurityType::None,
        Some(other) => {
            return Err(crate::common::Error::InvalidConfig(format!(
                "Unknown security type: {}",
                other
            )));
        }
    };

    Ok(VlessConfig {
        uuid: outer.vless.uuid,
        server_addr: outer.vless.server_addr,
        server_port: outer.vless.server_port,
        security,
        host: outer.vless.host,
        sni: outer.vless.sni,
        path: outer.vless.path.unwrap_or_else(|| "/".to_string()),
        tls_insecure: outer.vless.tls_insecure.unwrap_or(false),
    })
}

fn parse_hysteria2_config(json_str: &str) -> crate::common::Result<Hysteria2Config> {
    use serde::Deserialize;

    #[derive(Deserialize)]
    struct OuterConfig {
        hysteria2: InnerConfig,
    }

    #[derive(Deserialize)]
    struct InnerConfig {
        server_addr: String,
        server_port: u16,
        password: String,
        sni: Option<String>,
        obfs: Option<String>,
        obfs_password: Option<String>,
        tls_insecure: Option<bool>,
    }

    let outer: OuterConfig = serde_json::from_str(json_str)
        .map_err(|e| crate::common::Error::InvalidConfig(format!("JSON parse error: {}", e)))?;

    Ok(Hysteria2Config {
        server_addr: outer.hysteria2.server_addr,
        server_port: outer.hysteria2.server_port,
        password: outer.hysteria2.password,
        sni: outer.hysteria2.sni,
        obfs: outer.hysteria2.obfs,
        obfs_password: outer.hysteria2.obfs_password,
        tls_insecure: outer.hysteria2.tls_insecure.unwrap_or(false),
    })
}
