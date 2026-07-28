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

The repository does not commit generated or third-party `.so` files. The
native preparation script downloads the pinned `tdlib 1.6.0` archive, verifies
its SHA-256 digest, and extracts only the Android `libtdjson.so` files into the
ignored `.deps/` directory:

```bash
extensions/telegram/scripts/prepare_tdlib.sh
```

For offline CI, set `TDLIB_ARCHIVE_PATH` to an already downloaded verified
archive. Gradle may also use a separately managed binary directory through
`TDLIB_JNI_DIR`.

## Build

```bash
extensions/telegram/scripts/prepare_tdlib.sh

cd android
TARGET_ABI=arm64-v8a ./gradlew assembleRelease
TARGET_ABI=armeabi-v7a ./gradlew assembleRelease
```

`TARGET_ABI` is required. Verify the APK contains only the selected ABI before
publishing it to the optional-plugin release manifest. This project has no
Flutter/Dart dependency and does not use `pubspec.yaml` or the pub cache.
