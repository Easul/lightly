use jni::objects::JString;
use jni::signature::JavaType;
use jni::sys::{jint, jlong};
use jni::JNIEnv;

#[no_mangle]
pub extern "system" fn Java_com_proxy_core_ProxyCore_nativeInit(
    mut env: JNIEnv,
    _class: jni::objects::JClass,
    log_level: JString,
) -> jint {
    let level: String = env.get_string(&log_level).unwrap().into();
    crate::common::init_logging(&level);
    0
}

#[no_mangle]
pub extern "system" fn Java_com_proxy_core_ProxyCore_nativeStart(
    _env: JNIEnv,
    _class: jni::objects::JClass,
    _listen_addr: JString,
    _config: JString,
) -> jint {
    0
}

#[no_mangle]
pub extern "system" fn Java_com_proxy_core_ProxyCore_nativeStop(
    _env: JNIEnv,
    _class: jni::objects::JClass,
) -> jint {
    0
}
