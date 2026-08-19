# Lightly Life Runtime companion

This is a pure Android companion APK for running the Android builds of
MindGit and Life Record. It has no Flutter engine and no business UI.

The service runs the bundled Android ELF files from the APK's extracted native
library directory. Its private runtime directory is used for workspaces, data,
and logs:

```text
/data/user/0/lightly.tool.plugin.liferuntime/files/runtime/
  workspaces/
  data/
  logs/
```

The first release intentionally exposes only fixed start/stop operations over
the signature-protected AIDL service. It does not expose arbitrary command
execution or a terminal. Android builds of `git`, `ssh`, and optional `rg`
will be added to `runtime/bin` as versioned tool assets; ordinary glibc Linux
binaries are not compatible with Android's bionic runtime.

The default bind address is `127.0.0.1`. LAN binding is an explicit caller
option and must be paired with application authentication before release.

## Local smoke test

Build the Android arm64 Go binaries first. Life Record uses CGO/SQLite, so an
Android NDK compiler is required:

```bash
export ANDROID_NDK_HOME="$HOME/software/android/sdk/ndk/28.2.13676358"
export CC_ANDROID_ARM64="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android31-clang"
extensions/life-runtime/tools/build_runtime.sh
```

Build the host and install the current Lightly APK before installing this
companion. The host and companion must use the same signing certificate:

```bash
scripts/build_multi_abi.sh

PLUGIN_VERSION_CODE="$((5000 + $(git rev-list --count main)))" \
PLUGIN_VERSION_NAME="local+$(git rev-parse --short HEAD)" \
TARGET_ABI="arm64-v8a" \
LIFE_RUNTIME_BIN_DIR="$PWD/extensions/life-runtime/runtime/bin" \
extensions/telegram/android/gradlew \
  -p extensions/life-runtime/android --offline \
  :app:assembleRelease

adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
adb install -r extensions/life-runtime/android/app/build/outputs/apk/release/app-release.apk
```

Open Lightly -> 小工具 -> 人生运行时. The APK can also be installed directly
with `adb`; a release `plugins.json` is only needed for Lightly's downloader.
The smoke-test bundle does not yet include `git`, `ssh`, or `rg`, so MindGit's
Git operations remain unavailable until those Android tools are added. The
current runtime binaries are arm64; build and install the matching arm64
companion on a 64-bit Android device.
