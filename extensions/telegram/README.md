# Lightly Telegram native plugin

Pure Android companion APK for Lightly's Telegram tools. It has no Flutter
engine and no business UI. Lightly keeps the existing Telegram pages,
configuration, backup/import, and scheduling; this APK owns TDLib and its
private login session.

## Runtime contract

- Package: `lightly.tool.plugin.telegram`
- Feature metadata: `telegram`, API `1`
- Exported component: signature-protected `TelegramPluginService`
- IPC: AIDL using TDLib's JSON client API
- Native libraries: `libtdjson.so` and the small `libtelegram_bridge.so`

The duplicated AIDL files in Lightly and this plugin must remain byte-for-byte
compatible. Release APKs must use the same signing certificate as Lightly.

## TDLib binary source

The repository does not commit generated or third-party `.so` files. Run
`flutter pub get` once in this directory to fetch the pinned `tdlib 1.6.0`
package. Gradle then reads its `jniLibs` directory. CI may instead set
`TDLIB_JNI_DIR` to a verified TDLib binary directory.

## Build

```bash
flutter pub get

cd android
TARGET_ABI=arm64-v8a ./gradlew assembleRelease
TARGET_ABI=armeabi-v7a ./gradlew assembleRelease
```

`TARGET_ABI` is required. Verify the APK contains only the selected ABI before
publishing it to the optional-plugin release manifest.
