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
- Dedicated EasyTier, video, data-management, and simple-file-manager pages

`lib/theme/app_theme.dart` is the shared source for colors, typography, buttons, inputs, lists, dialogs, and bottom sheets. The settings home uses white blocks split by feature domain; short action menus use a compact grid, while longer action menus use plain text lists. The shared settings row lives in `lib/widgets/shared/setting_tile.dart`.

See [UI Design Guidelines](ui-design.en.md) for the complete constraints. UI refactors must not change WebView keep-alive behavior, proxy connections, remote-control sockets, or background service lifecycles.

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
- Touch, keyboard, global action, wake-screen, trajectory swipe, and annotation injection
- Two-way WebRTC voice, preferring the proven remote-control TCP target address when running over EasyTier
- Clipboard and status-message coordination

### Local Services
- HTTP file service
- Simple file manager service: local web file tree, text editing/saving, delete confirmation, and favorite paths
- Clipboard HTTP service

### EasyTier / P2P
- VPN and no-tun/no-VPN runtime modes
- No-VPN remote control reaches virtual IP targets through the EasyTier no-tun SOCKS5 portal
- Signature-permission protected EasyTier state provider for same-signature Monitor apps

## Platform Layer

Native code lives under `android/app/src/main/kotlin/` and `jniLibs/`:

- `MainActivity.kt`: bridge between Flutter and native capabilities
- `ScreenCapture.kt`: screen capture and AVC encoding, including encoder-size fallback for device compatibility
- `H264Decoder.kt`: video decoding
- `RemoteControlAccessibilityService.kt`: remote input, global actions, annotations, and disconnect prompts
- `EasyTierInfoProvider.kt` / `EasyTierStateStore.kt`: EasyTier state sharing
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

### Simple File Manager Path

```text
Settings → SimpleFileManagerService
  → Dart HttpServer (default 12580)
  → Web file tree / editor
  → safe read / save / delete under configured root
```

## Performance Notes

- Browser progress updates are throttled to avoid rebuild churn
- Proxy and WebSocket hot paths avoid verbose per-packet logging
- Scroll position and video detection use thresholds / debouncing
- WebViews, services, and streams should be disposed promptly

## Related Docs

- [Quick Start](quickstart.en.md)
- [Development Guide](development.en.md)
- [UI Design Guidelines](ui-design.en.md)
- [Browser / Remote Module Map](browser_remote_module_map.md)
- [Browser Regression Checklist](browser_regression_checklist.md)
- [Remote Control Regression Checklist](remote_control_regression_checklist.md)
- [v1.0.7 Release Summary](release-summary-v1.0.7.en.md)
