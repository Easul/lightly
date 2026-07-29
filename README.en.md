# Lightly

[中文](README.md)

Lightly is a Flutter-based Android browser and device toolbox with built-in **remote control** capabilities, alongside VLESS proxy support, EasyTier P2P VPN, media playback, local file serving, simple file management, and clipboard sync.

The project aims to keep browsing, connectivity, transfer, and device-control tools inside one lightweight and clearly organized interface instead of exposing a collection of unrelated screens.

## Features

### Remote Control
- **Real-time screen capture**: view your device screen from a browser, with encoder-size fallback for devices that reject full-resolution AVC capture
- **Remote touch control**: click and swipe on the web page to control the device in real time
- **Enhanced remote actions**: keyboard input, trajectory swipes, remote annotations, wake-screen, temporary close, and controller minimization
- **WebRTC voice chat**: two-way voice between controller and receiver, with EasyTier sessions preferring the proven remote-control path
- **Clipboard sync**: bidirectional clipboard sharing
- **Web-based control interface**: no client installation needed; any browser on the same LAN can take control

### Browser
- Full WebView-based browsing experience
- Tab management and session restore
- Address bar suggestions and favorites entry points
- Favorites management, long-press page actions, and a compact More tools panel
- Video detection, floating playback, and background audio
- Download management (with independent deletion of download records and files), site-data clearing, and browser history management
- Desktop mode and mobile viewport switching, web debug console
- Paginated action panel for narrow screens

### Networking
- VLESS over WebSocket / TLS / XUDP
- Local mixed proxy server (HTTP + SOCKS5)
- Hysteria2 / SOCKS5 proxy protocol support with diagnostic logging
- EasyTier P2P VPN integration for remote control over virtual IPs
- LAN file server and clipboard sync
- Simple file manager: browse a local web file tree, edit/save/delete text files, and favorite common paths

### Other Tools
- Native video playback (with media cache and speed test controls, millisecond-level time overlay)
- AI translation and chat tools
- Telegram check-in tool and message text selection
- Calculator and 2048 utility pages

### Optional Plugins
- Telegram, WebRTC voice, and EasyTier ship as same-signed pure-Android companion APKs
- Lightly embeds compatible plugin URLs, ABI entries, sizes, and SHA-256 values instead of trusting a runtime remote manifest
- Downloads support the configured Lightly proxy, direct GitHub access, timeout/sustained-slow mirror fallback, and a user-defined HTTPS mirror prefix
- GitHub Actions build Lightly and all six ABI-specific plugin APKs with one release key and cross-check certificates before publishing

## Interface and Interaction

- A muted green accent, soft gray background, and white content groups reduce heavy black surfaces and highly saturated warning colors
- Settings are split into browsing, network/service, and remote-control groups instead of one continuous stack of large cards
- Short action sheets use a compact grid, long action sheets use plain text rows, and confirmation dialogs stay small with clear action hierarchy
- The theme color represents normal and active states; danger colors are reserved for exit, delete, disconnect, and error actions
- Video, remote-screen, and keyboard surfaces keep dark backgrounds where they are functionally necessary

See [UI Design Guidelines](docs/ui-design.en.md) for design tokens, modal patterns, and component constraints.

## Installation

Download APKs from [GitHub Releases](https://github.com/Easul/lightly/releases).

Recommended variants:
- `app-arm64-v8a-release.apk` for 64-bit Android devices
- `app-armeabi-v7a-release.apk` for 32-bit Android devices

Requirements:
- Android 7.0+

## Quick Start

1. Install and open the app
2. Start browsing from the home page
3. **Remote control**: open **Settings → Remote Control**, start the service, and visit the shown LAN address from another browser to take control
4. To use a proxy, open **Settings → Proxy** and configure a VLESS node
5. To use P2P VPN, open **Settings → P2P VPN** and configure EasyTier
6. To edit files in a browser, open **Settings → 文件简易管理** and visit `http://127.0.0.1:12580` by default

## Documentation

### Chinese
- [Quick Start (CN)](docs/quickstart.md)
- [Development Guide (CN)](docs/development.md)
- [GitHub Release and Plugin Delivery (CN)](docs/github-release-delivery.md)
- [Optional Plugin Release Guide](docs/optional-plugin-release.md)
- [Plugin Delivery and YouTube Binary Change Summary (CN)](docs/release-summary-plugin-delivery.md)
- [Architecture (CN)](docs/architecture.md)
- [Architecture Migration Roadmap (CN)](docs/architecture-roadmap.md)
- [Engineering Maintenance Backlog (CN)](docs/maintenance-backlog.md)
- [Remote Control Architecture (CN)](docs/remote-control-architecture.md)
- [UI Design Guidelines (CN)](docs/ui-design.md)
- [Release Build Guide (CN)](docs/release_build.md)
- [Browser Regression Checklist (CN)](docs/browser_regression_checklist.md)
- [Remote Control Regression Checklist (CN)](docs/remote_control_regression_checklist.md)
- [Browser / Remote Module Map (CN)](docs/browser_remote_module_map.md)
- [v1.0.7 Release Summary (CN)](docs/release-summary-v1.0.7.md)
- [v1.0.8 Release Summary (CN)](docs/release-summary-v1.0.8.md)
- [EasyTier Build Notes (CN)](docs/easytier-build.md)
- [Sharing EasyTier State with Monitor (CN)](docs/easytier-state-sharing.md)

### English
- [Quick Start](docs/quickstart.en.md)
- [Development Guide](docs/development.en.md)
- [Architecture](docs/architecture.en.md)
- [Architecture Migration Roadmap](docs/architecture-roadmap.en.md)
- [Engineering Maintenance Backlog](docs/maintenance-backlog.en.md)
- [Remote Control Architecture](docs/remote-control-architecture.en.md)
- [UI Design Guidelines](docs/ui-design.en.md)
- [v1.0.7 Release Summary](docs/release-summary-v1.0.7.en.md)
- [v1.0.8 Release Summary](docs/release-summary-v1.0.8.en.md)
- [EasyTier Build Notes](docs/easytier-build.en.md)
- [Sharing EasyTier State with Monitor](docs/easytier-state-sharing.en.md)

## Tech Stack

- Flutter 3.41.6
- Dart 3.11.4
- Kotlin / Android SDK
- Rust EasyTier JNI integration
- `flutter_inappwebview`
- `sqflite` / `shared_preferences`

## Build

Development:

```bash
flutter pub get
flutter run --debug
```

Release builds:

```bash
bash scripts/build_multi_abi.sh
```

The release script produces separate 64-bit and 32-bit APKs. Android `versionCode` is `5000 + main branch commit count`, while the user-facing version uses `vX.Y.Z+<commit>`.

Before distributing a build, also follow the ABI, version, hash, and installation checks in [Release Build Guide](docs/release_build.md). Generated `target/`, `jniLibs/`, and APK outputs should not be committed.

## License

This project is released under the [MIT License](LICENSE).
