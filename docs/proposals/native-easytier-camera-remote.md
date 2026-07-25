# Native EasyTier Camera Remote Proposal

## Status and Scope

This is a separate-product proposal retained from earlier design work. It is not part of Lightly's
current runtime or architecture migration, and it must not be implemented inside Lightly merely as
a refactor.

The proposed product is a Kotlin-first Android app for two phones to communicate over EasyTier with
bidirectional audio and optional bidirectional camera video. It intentionally excludes browser,
proxy, MediaProjection screen sharing, and remote gesture control.

## Product Goal

- Either device may be the connector or listener.
- The controlled endpoint sends camera video and microphone audio.
- The controller sends talkback audio and may optionally send camera video.
- The control channel supports heartbeat, wake screen, microphone state, camera state/switch, and
  hangup.
- Target Android 5.0+ only if the selected WebRTC artifact and camera/audio stack pass an early
  feasibility spike.

## Reusable Lightly Knowledge

The new project may port concepts, but should not depend on Lightly source packages at runtime:

- EasyTier TOML schema and profile semantics:
  - top-level `instance_name`, `hostname`, `ipv4`/`dhcp`, `listeners`, `socks5_proxy`
  - `[network_identity]` for name/secret
  - repeated `[[peer]]`
- EasyTier JNI startup, VPN permission, virtual-IP readiness polling, route normalization, and
  explicit VPN stop behavior.
- Network-info parsing from top-level `map[instanceName]`.
- EasyTier WebRTC host-candidate preference/rewrite for `10.126.*` peers.
- Voice-communication audio mode, AEC/NS, route refresh, and bounded diagnostic logging.
- Newline-delimited JSON signaling patterns for offer/answer/candidate and state commands.

Do not port:

- browser/VLESS/proxy modules
- `RemoteControlAccessibilityService`
- MediaProjection, `ScreenCapture`, H.264 screen transport, or gesture overlays
- Lightly's internal-proxy remote-control path

## Suggested Architecture

```text
app/
├── data/
│   ├── EasyTierConfig.kt
│   ├── EasyTierProfile.kt
│   └── EasyTierProfileStore.kt
├── easytier/
│   ├── EasyTierManager.kt
│   ├── EasyTierNetworkInfoAnalyzer.kt
│   ├── EasyTierRouteNormalizer.kt
│   └── EasyTierVpnService.kt
├── signaling/
│   ├── SignalMessage.kt
│   ├── SignalCodec.kt
│   ├── SignalServer.kt
│   ├── SignalClient.kt
│   └── SessionController.kt
├── rtc/
│   ├── RtcSession.kt
│   ├── RtcMediaController.kt
│   ├── RtcCandidateFilter.kt
│   └── RtcStatsLogger.kt
├── platform/
│   ├── WakeScreenController.kt
│   ├── PermissionController.kt
│   └── AudioRouteController.kt
└── ui/
    ├── MainActivity.kt
    ├── EasyTierSettingsScreen.kt
    ├── DeviceListScreen.kt
    └── SessionScreen.kt
```

## Runtime Flow

1. Load or edit an EasyTier profile.
2. Parse TOML and request VPN permission.
3. Start the EasyTier instance.
4. Poll network info until the active instance has a virtual IPv4.
5. Start `EasyTierVpnService`, pass the TUN fd, and display reachable peers.
6. Listen or connect on a fixed control port such as `19080`.
7. Exchange hello/capabilities and WebRTC signaling over control TCP.
8. Establish bidirectional audio; enable endpoint camera by default and controller camera optionally.
9. Keep heartbeat and state-based commands on the control channel.

## Media Design

- Prefer one Unified Plan `PeerConnection`.
- Add local audio tracks before the initial offer.
- Pre-create an optional controller video sender with a disabled track to avoid repeated
  renegotiation on older devices.
- Use Camera2 where reliable and retain a Camera1 fallback if the chosen WebRTC SDK supports it.
- Use voice-communication audio mode with AEC/NS. Avoid aggressive gain boosts.
- Keep the controlled endpoint camera primary; use lower resolution/fps for controller return video
  on low-end devices.

## Signaling Shape

Use newline-delimited JSON over TCP initially. Commands should be idempotent and state-based.

```json
{"type":"hello","id":1,"ts":123,"data":{"role":"controller","capabilities":["audio","video","wake_screen"]}}
{"type":"heartbeat","id":2,"ts":123}
{"type":"status","action":"webrtc_offer","id":3,"ts":123,"data":{"sdp":"...","type":"offer"}}
{"type":"status","action":"webrtc_candidate","id":4,"ts":123,"data":{"candidate":"...","sdpMid":"0","sdpMLineIndex":0}}
{"type":"command","action":"set_remote_mic","id":5,"ts":123,"data":{"enabled":false}}
{"type":"command","action":"switch_camera","id":6,"ts":123,"data":{"target":"local"}}
```

## Android Requirements

Baseline permissions/capabilities:

- `INTERNET`, network-state permissions
- `CAMERA`, `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`
- `WAKE_LOCK`
- `FOREGROUND_SERVICE` and target-SDK-specific camera/microphone service types if capture continues
  in background
- `BIND_VPN_SERVICE` on the EasyTier VPN service
- Bluetooth permissions appropriate to the target SDK

The app should not request accessibility or MediaProjection permissions.

## Delivery Phases

1. WebRTC Android 5 feasibility spike without EasyTier.
2. Native EasyTier start/stop, profile storage, virtual IP, and peer list.
3. Bidirectional TCP control channel over EasyTier.
4. Bidirectional WebRTC audio over LAN and EasyTier.
5. Endpoint camera to controller.
6. Optional controller camera return.
7. Diagnostics, reconnect, packaging, and long-run testing.

## Major Risks

- Modern WebRTC artifacts may not work reliably on API 21 hardware.
- Both EasyTier `.so` files and correct ELF dependencies are required for each ABI.
- EasyTier startup completion does not imply route/virtual-IP readiness.
- WebRTC may select unreachable Wi-Fi candidates instead of overlay candidates.
- Old devices may not encode and decode two camera streams simultaneously.
- Background wake/camera behavior is constrained by newer Android versions.

## First Milestone Exit Criteria

Before building the full product, prove all of the following on target-class hardware:

- selected WebRTC SDK installs and opens camera/microphone on the minimum Android version
- EasyTier obtains a virtual IP and stops cleanly
- control TCP works in both listener directions over `10.126.*`
- two-way audio remains stable over EasyTier

If any criterion fails, revise the minimum Android version or media design before porting more code.
