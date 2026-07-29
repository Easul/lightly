# Optional companion release

Use `scripts/build_optional_plugins.sh` to build Telegram, WebRTC voice, and EasyTier as signed,
single-ABI native companion APKs. The script injects one version label/code into all plugins,
rejects Flutter/Dart runtime artifacts, checks each APK for the selected ABI, verifies that all six
APKs share one signing certificate, and writes an ABI-aware `plugins.json` compatible with Lightly's
installer.

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
