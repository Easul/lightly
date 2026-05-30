# Lightly

[中文](README.md)

Lightly is a Flutter-based Android browser with built-in **remote control** capabilities, alongside VLESS proxy support, EasyTier P2P VPN, media playback, local file serving, and clipboard sync.

## Features

### Remote Control
- **Real-time screen capture**: view your device screen from a browser, with encoder-size fallback for devices that reject full-resolution AVC capture
- **Remote touch control**: click and swipe on the web page to control the device in real time
- **WebRTC voice chat**: two-way voice between controller and receiver, with EasyTier sessions preferring the proven remote-control path
- **Clipboard sync**: bidirectional clipboard sharing
- **Web-based control interface**: no client installation needed; any browser on the same LAN can take control

### Browser
- Full WebView-based browsing experience
- Tab management and session restore
- Address bar suggestions and favorites entry points
- Video detection, floating playback, and background audio
- Download management and site-data clearing

### Networking
- VLESS over WebSocket / TLS / XUDP
- Local mixed proxy server (HTTP + SOCKS5)
- EasyTier P2P VPN integration for remote control over virtual IPs
- LAN file server and clipboard sync

### Other Tools
- Native video playback
- Calculator and 2048 utility pages

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

## Documentation

### Chinese
- [Quick Start (CN)](docs/quickstart.md)
- [Development Guide (CN)](docs/development.md)
- [Architecture (CN)](docs/architecture.md)
- [EasyTier Build Notes (CN)](docs/easytier-build.md)

### English
- [Quick Start](docs/quickstart.en.md)
- [Development Guide](docs/development.en.md)
- [Architecture](docs/architecture.en.md)
- [EasyTier Build Notes](docs/easytier-build.en.md)

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

## License

This project is released under the [MIT License](LICENSE).
