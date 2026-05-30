# Lightly Quick Start

[中文](quickstart.md)

## Installation

1. Download the latest APK from [Releases](https://github.com/Easul/lightly/releases)
2. Pick the correct ABI build:
   - `app-arm64-v8a-release.apk` for 64-bit devices
   - `app-armeabi-v7a-release.apk` for 32-bit devices
3. Install it on Android and grant required permissions

## First Run

Recommended order for a first tour:

1. **Browser**: open a few pages and confirm basic browsing works
2. **Proxy**: open **Settings → Proxy** and configure a VLESS link
3. **Remote Control**: open **Settings → Remote Control**, start the service, and visit the shown LAN address from another browser
4. **P2P VPN**: open **Settings → P2P VPN** and configure EasyTier
5. **Local Services**: enable the HTTP file server and clipboard sync if needed

## When to Use Lightly

| Scenario | How to Use |
|----------|------------|
| **Remote control between phones** | Open another phone's remote control address in your phone's browser to view and control the screen in real time |
| **Remote control across networks** | Configure EasyTier and use the virtual IP path for remote control and WebRTC voice |
| **LAN clipboard sync** | Copy on device A → paste on device B, no third-party cloud service needed |
| **Access proxy sites** | Configure a VLESS node and browse sites that require proxy via WebView |
| **File transfer between devices** | Enable the HTTP file service and upload/download via browser |
| **Background video playback** | When the browser detects a video, tap the floating player and continue listening after switching to background |

## Core Capabilities

### Browser
- Multi-tab browsing
- Address bar suggestions
- Video detection and floating playback
- Download management

### Proxy
- VLESS over WebSocket / TLS
- Local mixed proxy support (HTTP / SOCKS5)

### Remote Control
- Screen capture, with compatible encoder-size fallback on devices that reject full-resolution AVC capture
- Touch injection
- Two-way WebRTC voice and clipboard sync

**Control Interface Operations:**
- Tap/Single-finger tap = Phone touch tap
- Drag/Single-finger swipe = Swipe phone screen
- Pinch zoom = Zoom phone screen
- Phone video/audio will sync to browser playback

### Local Services
- HTTP file server (default 3001)
- Clipboard HTTP service (default 12345)

## Common Issues

### Proxy cannot connect
- Check the VLESS link format
- Verify host, path, and sni values
- Confirm the remote service is reachable

### Remote control page will not open
- Make sure both devices are on the same LAN
- Make sure the remote-control service is enabled
- Check whether the port is already in use

### Remote screen is black or voice drops
- First confirm the network is stable; EasyTier fluctuations trigger automatic reconnects, but weak networks can still cause brief black screens or silence
- On devices such as some Redmi models, the app automatically retries lower capture resolutions if full-resolution AVC encoding is rejected
- If the controller speaks but the receiver stops hearing audio, toggling voice can refresh the audio route; newer builds also detect receiver-side remote-audio stalls and recover automatically

### Video playback behaves unexpectedly
- Try clearing site data or cache first
- Confirm the current site allows in-app playback

## More Documentation

- [Development Guide](development.en.md)
- [Architecture](architecture.en.md)
