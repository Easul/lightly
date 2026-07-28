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
`PLUGIN_VERSION_NAME`, `MINIMUM_LIGHTLY_VERSION_CODE`, `PLUGIN_RELEASE_TAG`, or
`PLUGIN_OUTPUT_DIR` when preparing a release. The script compares every plugin signing certificate
with `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`; set `LIGHTLY_APK` explicitly when
the matching host APK is elsewhere. Upload the six `*-release.apk` files and
`plugins.json` to the matching GitHub release in `Easul/lightly-plugins`.

Prepare Telegram's TDLib binary first:

```bash
extensions/telegram/scripts/prepare_tdlib.sh
```

Do not publish the manifest until the corresponding APKs are signed with the same certificate as
the Lightly build that declares the minimum version code.
