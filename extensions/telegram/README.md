# Lightly Telegram plugin

Optional companion APK for Lightly's Telegram tools. The plugin owns TDLib and
its private login session. Lightly remains the owner of Telegram API/check-in
configuration so existing backup export/import continues to work.

The APK must be signed with the same certificate as its Lightly host. Release
builds reuse `android/app/upload-keystore.jks` from the repository root when it
is available.

Build one ABI at a time:

```bash
TARGET_ABI=arm64-v8a flutter build apk --release --target-platform android-arm64 \
  --obfuscate --split-debug-info=build/symbols
TARGET_ABI=armeabi-v7a flutter build apk --release --target-platform android-arm \
  --obfuscate --split-debug-info=build/symbols
```

`TARGET_ABI` is required because TDLib's Android library publishes multiple
native slices that Flutter's target platform alone does not exclude.
