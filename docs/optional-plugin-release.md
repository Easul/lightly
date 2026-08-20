# Optional companion release

Use `scripts/build_optional_plugins.sh` to build Telegram, WebRTC voice, EasyTier, and the Life
Runtime as signed native companion APKs. The script injects one version label/code into all
plugins, rejects Flutter/Dart runtime artifacts, checks native ABI contents where applicable,
verifies that all companion APKs share one signing certificate, and writes an ABI-aware
`plugins.json` compatible with Lightly's installer.

```bash
scripts/build_optional_plugins.sh
```

The default output directory is `build/optional-plugins/`. Override `PLUGIN_VERSION_CODE`,
`PLUGIN_VERSION_NAME`, `TELEGRAM_PLUGIN_API_VERSION`, `WEBRTC_PLUGIN_API_VERSION`,
`EASYTIER_PLUGIN_API_VERSION`, `MINIMUM_LIGHTLY_VERSION_CODE`, `PLUGIN_RELEASE_TAG`, or
`PLUGIN_OUTPUT_DIR` when preparing a release. `PLUGIN_API_VERSION` remains a compatibility fallback
for Telegram and EasyTier only; WebRTC defaults independently to API 3. The script compares every plugin signing certificate
with `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`; set `LIGHTLY_APK` explicitly when
the matching host APK is elsewhere. Upload the six `*-release.apk` files and
`plugins.json` to the matching GitHub release in `Easul/lightly-plugins`.

The host build script keeps its normal main-commit version rule by default. For an explicitly
requested compatibility rebuild, pass the matching `RELEASE_VERSION_NAME` and
`RELEASE_VERSION_CODE` to `scripts/build_multi_abi.sh`, then pass those same values as
`PLUGIN_VERSION_NAME` and `PLUGIN_VERSION_CODE` to `scripts/build_optional_plugins.sh`.

Prepare Telegram's TDLib binary first:

```bash
extensions/telegram/scripts/prepare_tdlib.sh
```

Every Service-owning companion must include the protected transparent
`PluginBootstrapActivity` and Lightly must activate it through
`OptionalPluginActivationCoordinator` before the initial bind. This is required for OEM builds
that reject direct cross-package background-service activation. The bootstrap does not provide UI;
it returns immediately to the foreground Lightly Activity. Keep `android:icon` and
`android:roundIcon` pointed at the copied Lightly launcher resources in every companion manifest.

Do not publish the manifest until the corresponding APKs are signed with the same certificate as
the Lightly build that declares the minimum version code.

## Life Runtime

`extensions/life-runtime` is a pure Android companion. It owns the private runtime directory,
starts the Android builds of `mindgit` and `liferecord`, and exposes only fixed start/stop/status
operations over a signature-protected AIDL service. It does not provide a shell or arbitrary
host-side command API. Android-native executables are packaged as extracted native libraries;
ordinary glibc Linux binaries are not compatible with Android's bionic linker.

Use `LIFE_RUNTIME_BIN_DIR` to point the companion build at a directory containing Android
executables. The expected names are `mindgit` and `liferecord`. Set `LIFE_RUNTIME_GIT_DIR` to the
pinned Termux Android runtime prepared by `extensions/life-runtime/tools/prepare_git_runtime.sh`;
it supplies Git, SSH, ripgrep, zip, and unzip. Basic file commands use Android toybox and still run
under the companion UID. A LAN bind requires an explicit option; MindGit always requires an access
password of at least eight characters.

User content, service configuration, data, and logs live below
`files/runtime/workspaces`. MindGit `-d` paths, Life Record content paths, and Life Record data paths
are relative to that workspace root and must not escape it. Life Record's default paths are
`summary`, `life-record/config.yaml`, `life-record/data`, and `life-runtime/logs`.

## Pinned delivery and GitHub Actions

The release workflow builds the six companion APKs before the final Lightly APK, writes their exact
URLs, sizes, and SHA-256 values to `plugins.json`, and embeds that file at
`assets/optional_plugins/plugins.json`. The runtime installer reads the signed in-APK manifest; it
does not trust `releases/latest/download/plugins.json`.

At runtime, automatic delivery tries GitHub through the active Lightly proxy when available, or
directly otherwise. A connection timeout, idle timeout, HTTP/redirect failure, or sustained speed
below 48 KiB/s after the initial eight-second window causes a fresh direct mirror attempt. The
Settings -> Plugin Download page also provides GitHub-only, mirror-only, and a custom HTTPS mirror
prefix. IP geolocation is deliberately not used to choose a route.

The workflow publishes the optional-plugin Release before the Lightly Release. Configure
`PLUGIN_RELEASE_REPOSITORY`, `PLUGIN_RELEASE_TOKEN`, `YOUTUBE_RESOLVER_AAR_URL`, and
`YOUTUBE_RESOLVER_AAR_SHA256` as described in
[GitHub Release and Plugin Delivery](github-release-delivery.md). The final host APK and all six
companion APKs are certificate-compared by `scripts/verify_optional_plugin_bundle.sh`.

## Migration acceptance (2026-07-29)

The native companion extraction is implementation-complete. The following manual matrix was
verified on physical devices in addition to the automated host/plugin tests and release-content
checks:

- LAN and EasyTier WebRTC voice worked in both directions. Disconnect cleanup, temporary close,
  full close, wired-headset routing, and Bluetooth-headset routing also completed normally.
- EasyTier was exercised on Android 7 and Android 10 across arm64/armeabi-v7a packages, VPN and
  no-tun modes, peer refresh, and remote-control runtime reuse.
- Lightly cold-started and unrelated features remained usable without optional plugins on Android 7
  and Android 13.
- A profile-signed plugin was rejected by the release host while the matching release-signed plugin
  worked. This is the expected same-signature isolation behavior, not a compatibility failure.
- Installing the new Lightly APK over the previous version preserved browser, proxy, remote-control,
  and Lightly-owned configuration.
- A full Lightly data export, app-data clear, and import restored the Lightly-owned configuration in
  scope for the unified backup.

These checks close the optional-plugin migration acceptance gate. Keep absence, disabled-package,
signature mismatch, incompatible API, corrupt download, and hash mismatch as explicit failure
states in future installer changes; none may block host cold start or unrelated features.

Google-account browser login cookies are a known non-blocking backup limitation. Unified backup can
round-trip the cookies exposed by Android WebView for indexed origins, but it does not guarantee
reconstruction of every Google authentication/session state across all related origins. Do not use
Google login-session restoration as a release blocker for the companion migration, and do not claim
that unified backup preserves every third-party login session.
