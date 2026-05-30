# Lightly Architecture

[中文](architecture.md)

## Overview

Lightly is an Android browser built primarily with Flutter, with Kotlin native modules and EasyTier Rust components for lower-level networking and media features.

At a high level, the app is split into three layers:

```text
UI layer (Flutter pages and widgets)
    ↓
Service layer (browser, proxy, remote control, file server, video)
    ↓
Platform layer (Android Kotlin, JNI, Rust EasyTier, MediaCodec)
```

## UI Layer

Most UI lives under `lib/pages/` and `lib/widgets/`:

- `BrowserPage`: main browser screen
- `SettingsPage`: settings entry point and feature toggles
- `ClipboardPage`: clipboard page
- Dedicated EasyTier, video, and data-management pages

## Service Layer

Most service logic lives under `lib/browser/` and `lib/services/`:

### Browser
- WebView hosting
- Tab management and restore
- Address suggestions, favorites, and download coordination

### Proxy
- `vless_client.dart`: VLESS protocol implementation
- `local_mixed_proxy_server.dart`: local HTTP + SOCKS5 mixed proxy server
- `proxy_service.dart`: proxy lifecycle and configuration

### Remote Control
- Screen capture and H.264 frame pipeline, with Android handling MediaProjection / MediaCodec encoding and Flutter handling socket transport plus decode display
- Touch, keyboard, and global action injection
- Two-way WebRTC voice, preferring the proven remote-control TCP target address when running over EasyTier
- Clipboard and status-message coordination

### Local Services
- HTTP file service
- Clipboard HTTP service

## Platform Layer

Native code lives under `android/app/src/main/kotlin/` and `jniLibs/`:

- `MainActivity.kt`: bridge between Flutter and native capabilities
- `ScreenCapture.kt`: screen capture and AVC encoding, including encoder-size fallback for device compatibility
- `H264Decoder.kt`: video decoding
- EasyTier JNI / Rust `.so` files: P2P VPN runtime

## Key Data Flows

### Browser Proxy Path

```text
Browser WebView
  → LocalMixedProxyServer
  → VlessClient
  → Remote VLESS server
  → response back to WebView
```

### EasyTier VPN Path

```text
Flutter UI
  → MethodChannel
  → Kotlin wrapper
  → EasyTier JNI
  → Rust easytier core
  → Android VpnService / tun
```

### Remote Control Path

```text
LAN browser
  → Remote control HTTP interface
  → Android capture / input services
  → screen / touch / clipboard / audio
```

Remote-control responsibilities are split into connection flow, message routing, screen-frame pipeline, health monitoring, and voice coordination. See [Browser / Remote Module Map](browser_remote_module_map.md).

## Performance Notes

- Browser progress updates are throttled to avoid rebuild churn
- Proxy and WebSocket hot paths avoid verbose per-packet logging
- Scroll position and video detection use thresholds / debouncing
- WebViews, services, and streams should be disposed promptly

## Related Docs

- [Quick Start](quickstart.en.md)
- [Development Guide](development.en.md)
