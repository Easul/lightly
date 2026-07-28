#include <jni.h>

#include <string>

extern "C" {
int td_create_client_id();
void td_send(int client_id, const char *request);
const char *td_receive(double timeout);
const char *td_execute(const char *request);
}

namespace {

std::string to_string(JNIEnv *env, jstring value) {
    if (value == nullptr) {
        return {};
    }
    jclass string_class = env->FindClass("java/lang/String");
    jmethodID get_bytes = env->GetMethodID(
        string_class,
        "getBytes",
        "(Ljava/lang/String;)[B");
    jstring encoding = env->NewStringUTF("UTF-8");
    auto bytes = static_cast<jbyteArray>(
        env->CallObjectMethod(value, get_bytes, encoding));
    env->DeleteLocalRef(encoding);
    env->DeleteLocalRef(string_class);
    if (bytes == nullptr || env->ExceptionCheck()) {
        return {};
    }
    const jsize length = env->GetArrayLength(bytes);
    std::string result(static_cast<size_t>(length), '\0');
    env->GetByteArrayRegion(
        bytes,
        0,
        length,
        reinterpret_cast<jbyte *>(result.data()));
    env->DeleteLocalRef(bytes);
    return result;
}

jstring to_jstring(JNIEnv *env, const char *value) {
    if (value == nullptr) {
        return nullptr;
    }
    const auto length = static_cast<jsize>(std::char_traits<char>::length(value));
    jbyteArray bytes = env->NewByteArray(length);
    env->SetByteArrayRegion(
        bytes,
        0,
        length,
        reinterpret_cast<const jbyte *>(value));
    jclass string_class = env->FindClass("java/lang/String");
    jmethodID constructor = env->GetMethodID(
        string_class,
        "<init>",
        "([BLjava/lang/String;)V");
    jstring encoding = env->NewStringUTF("UTF-8");
    auto result = static_cast<jstring>(
        env->NewObject(string_class, constructor, bytes, encoding));
    env->DeleteLocalRef(encoding);
    env->DeleteLocalRef(bytes);
    env->DeleteLocalRef(string_class);
    return result;
}

}  // namespace

extern "C" JNIEXPORT jint JNICALL
Java_lightly_tool_plugin_telegram_TelegramNativeBridge_createClient(
    JNIEnv *,
    jobject) {
    return td_create_client_id();
}

extern "C" JNIEXPORT void JNICALL
Java_lightly_tool_plugin_telegram_TelegramNativeBridge_send(
    JNIEnv *env,
    jobject,
    jint client_id,
    jstring request_json) {
    const std::string request = to_string(env, request_json);
    td_send(client_id, request.c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_lightly_tool_plugin_telegram_TelegramNativeBridge_receive(
    JNIEnv *env,
    jobject,
    jdouble timeout_seconds) {
    return to_jstring(env, td_receive(timeout_seconds));
}

extern "C" JNIEXPORT jstring JNICALL
Java_lightly_tool_plugin_telegram_TelegramNativeBridge_execute(
    JNIEnv *env,
    jobject,
    jstring request_json) {
    const std::string request = to_string(env, request_json);
    return to_jstring(env, td_execute(request.c_str()));
}
