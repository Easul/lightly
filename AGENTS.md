# Project Notes for Future Agents

> **Agent 工作规则**：每次对话开始时，必须先阅读 `temp/agent_rules.md` 了解工作流程规范，再阅读本文件了解技术约束。
>
> **文件优先级**：`AGENTS.md`（技术约束）> `temp/rules.md`（用户要求/踩坑记录）> `temp/agent_rules.md`（工作流程）

## Quick Index

- Networking / proxy:
  - `## VLESS over WebSocket pitfalls`
  - `## Telegram SOCKS5 Compatibility Requirements`
  - `## Cloudflare-Challenged Site Compatibility`
- Browser / WebView runtime:
  - `## Minimal UI Design System`
  - `## WebView HTTP Auth & Popup Compatibility`
  - `## Selective Browsing Data Clearing`
  - `## Settings → BrowserPage State Refresh Pattern`
  - `## Lock Icon Site-Data Clearing Dialog`
- Build / release:
  - `## Build Size & Code Optimization Guidelines`
  - `## Git Artifact Hygiene`
  - `## Release Build (per-ABI packages)`
  - `## WebRTC Voice over EasyTier / Remote-Control Path`
- EasyTier native integration:
  - `## EasyTier Android Integration Notes`
- Other app features:
  - `## Native Video Parser Setting`
  - `## Local HTTP / Clipboard LAN Address Display`
  - `## Calculator Input / Compact Layout Rules`
  - `## Common Production Fixes (v1.0.1+2)`

## VLESS over WebSocket pitfalls

This project has two important real-world VLESS WS compatibility cases that must not be regressed:

1. `vless://...@example.com:2083?...host=vc.example.com&path=/speedtest&security=tls&sni=vc.example.com`
2. `vless://...@api.example.com:2095?...host=your-worker.example.workers.dev&path=/&packetEncoding=xudp`

### Do not regress these behaviors

- Keep the current `webSocketTlsServerName` vs `webSocketHttpHost` split in `lib/browser/vless_client.dart`.
  - TLS/SNI and HTTP `Host` are not interchangeable.
  - The visa node depends on correct TLS SNI + WS Host handling.

- Keep the current **combined first WebSocket frame** behavior in `VlessTunnel._writeWebSocketPayload()`.
  - The openai/workers-style node may fail or stall if the VLESS request and the first client payload are sent as separate early frames.
  - There is also a short fallback timer for server-speaks-first cases; do not remove it without re-testing both nodes.

- Do not move VLESS request sending earlier than the current listener setup.
  - Response listeners must be ready before the VLESS request is sent.
  - Earlier attempts caused missing responses / timeouts.

- Do not reintroduce upgraded-socket subscription reuse.
  - The current custom WS transport exists because the previous upgraded-socket path could lose inbound frames after manual HTTP 101 handling.

### Performance pitfalls

- Avoid verbose per-packet / per-frame logging in:
  - `lib/browser/vless_client.dart`
  - `lib/browser/local_mixed_proxy_server.dart`
- The openai/workers-style node amplifies hot-path overhead because traffic is more fragmented and frame frequency is higher.
- Do not reintroduce per-frame `flush()` behavior on WebSocket writes unless you have benchmarked it.
  - Serial `addStream(...)+flush()` on every frame caused noticeable browser lag.

### Browser/UI pitfalls

- Be careful with `setState()` inside high-frequency WebView callbacks in `lib/pages/browser_page.dart`.
  - `onProgressChanged`, `onTitleChanged`, and similar callbacks can easily cause visible jank.
  - Prefer change detection before calling `setState()`.

## Minimal UI Design System

- Treat `lib/theme/app_theme.dart` as the source of truth for shared colors, typography, controls, dialogs, bottom sheets, and list styling.
- Keep the app visually lightweight: muted theme green, soft gray page backgrounds, white grouped surfaces, dark-gray text instead of large pure-black areas, and low-saturation danger colors instead of bright red.
- Use compact icon grids for short action sets such as Browser More; use plain vertical text lists for longer action labels or URL-related actions.
- Browser More uses a 5-column grid on wider screens. Narrow screens use horizontally swipeable `4 x 2` pages with a page indicator, approximately `23`-pixel icons, `11.5`-pixel labels, and comfortable vertical spacing. Do not enlarge it back into a tall list or heavy icon-card layout without explicit design review.
- Settings entry pages should separate different feature domains into independent white blocks. Rows should remain simple title/subtitle/chevron items rather than separate large outlined cards with colored icon containers.
- Reserve dark surfaces for functionally immersive contexts such as video, remote-screen viewing, and remote keyboard controls.
- Reserve danger colors for actual error, delete, stop, disconnect, and exit actions. Prefer `ColorScheme.error` / `errorContainer` over direct `Colors.red` usage.
- UI-only refactors must not change WebView keepAlive behavior, overlay timing, proxy connections, remote-control sockets, or service lifecycles.
- Detailed tokens and component patterns are documented in `docs/ui-design.md` and `docs/ui-design.en.md`.

### Browser performance constraints

These patterns were introduced to eliminate jank during normal browsing. Do not regress them:

- **Progress updates must not rebuild the entire page.**
  - `BrowserWebViewHost` receives progress via `ValueListenable<int>` (`progressListenable`) and refreshes only the `LinearProgressIndicator` through `ValueListenableBuilder`.
  - `BrowserPage` no longer calls `setState()` on every `onProgressChanged` tick.
  - If you change the progress bar implementation, keep it isolated from the parent scaffold rebuild.

- **Throttle progress ticks before updating UI.**
  - `_updateProgressIfNeeded()` in `lib/pages/browser_page.dart` only updates when progress is `0`, `100`, or changes by at least `5` percentage points.
  - Do not remove this threshold; raw progress callbacks fire dozens of times per page load.

- **Scroll position must not be written on every pixel.**
  - `_updateScrollPositionIfNeeded()` only writes to `BrowserTabService` when scroll delta exceeds `24` pixels.
  - `BrowserTabService.updateTab()` also performs change detection and returns `false` when no field actually changed, avoiding unnecessary object churn.

- **Keep `isLoading` state stable during progress ticks.**
  - `onProgressChanged` must NOT update `isLoading`. Only `onLoadStart` / `onLoadStop` / error handlers should toggle it.
  - This prevents the bottom-bar reload icon from flickering during every progress update.

- **Overlay animations must not compete with BrowserPage rebuilds.**
  - While drawer / bottom sheets are opening or closing, defer non-critical `setState()` calls and batch one rebuild after the overlay settles.
  - WebView callbacks, favorite-status notifications, secure-state changes, and load-stop follow-ups can still arrive behind overlays; do not let them rebuild the full BrowserPage during the animation.
  - Resume WebView timers/video after the overlay settle delay rather than synchronously in the same frame that dismisses the overlay.

- **Tab switcher layout must stay cheap during sheet animation.**
  - Avoid `shrinkWrap` in the tab switcher list when it is already inside a bounded `Flexible`/sheet container.
  - Prefer stable item extents for tab rows so Flutter does not remeasure every tab card while the bottom sheet animates.

- **Address bar typing must not trigger parent rebuilds.**
  - `BrowserAddressBar` already manages its own internal state and overlay. `BrowserPage` passes empty `onChanged` / `onClear` callbacks instead of `setState(() {})`.

- **Video detection script must be debounced.**
  - The injected `MutationObserver` in `_injectVideoDetectionScript()` uses a `180ms` debounce (`scheduleReport`) instead of calling `reportVideo()` on every DOM mutation.
  - Removing this debounce will cause continuous JS overhead on dynamic pages.

- **Retained WebViews must not be trimmed during tab-preserving UI transitions.**
  - Normal overlays and routine tab close/switch transitions should not dispose background `InAppWebViewKeepAlive` objects.
  - Android platform-view disposal can race with the next WebView attach and surface as white screens or stale content from a closed tab.
  - When loading a real URL from the favorites pseudo-page, or when the active tab has no live WebView controller, recreate the active tab keepAlive before rebuilding so the requested URL gets a fresh native WebView.

- **Long overlays should stop loading only after a delay.**
  - Do not call `stopLoading()` immediately when opening the drawer or tab switcher; quick overlays should only soft-freeze.
  - If the same active real WebView tab is still loading after the delay, stop that load and reload the same URL after the overlay settles, provided the active tab and URL still match.

## Required verification when touching VLESS / proxy / WebView code

Run at least these commands:

```bash
flutter test test/browser/proxy_service_test.dart
cargo test --manifest-path rust/proxy-core/Cargo.toml
flutter build apk --release
```

If the change touches VLESS WS behavior, manually verify both nodes through the local proxy path, not just unit tests.

Recommended smoke check pattern:

1. Start the local proxy with the target VLESS node.
2. Send a real HTTPS request through it (for example with `curl -I -x http://127.0.0.1:<port> https://example.com`).
3. Confirm both:
   - `visa ws-tls` node still works
   - `openai workers xudp` node still works

## Telegram SOCKS5 Compatibility Requirements

This project now includes a mixed HTTP + SOCKS5 proxy. Telegram has specific SOCKS5 requirements that must not be regressed:

### Authentication Method Negotiation

- Telegram sends multiple authentication methods (e.g., 0x00 no-auth and 0x02 username/password).
- The proxy MUST select one method in the reply (0x00 or 0x02), or 0xFF if none acceptable.
- The active SOCKS5 implementation used by Android release builds now lives in `rust/proxy-core/src/inbound/socks5.rs`; keep repo-level Dart wrappers and Rust core behavior aligned.
- When a client offers both 0x00 and 0x02, prefer 0x00 unless this repo adds real end-to-end authenticated SOCKS5 enforcement. Telegram can advertise both methods even when the working path is no-auth.
- **Do not hardcode** to username/password when the server is not actually enforcing credentials; that can break otherwise healthy Telegram proxy handshakes.

### CONNECT Success Reply Format

- Telegram is sensitive to SOCKS5 CONNECT success reply `BND.ADDR`/`BND.PORT` fields.
- Must be the **actual relay bind address and port**, not zeros or placeholders.
- In the Rust proxy core, first use `VlessStream::local_bind_addr()`. If that is unavailable or unspecified, fall back to the local listener address with a concrete loopback IP instead of any zero placeholder.
- **Do not send** `0.0.0.0:0` or `[::]:0` as placeholder; Telegram rejects it.

### Half-Close Semantics

- Telegram expects proper half-close semantics: client input EOF should not immediately tear down the entire tunnel.
- In `rust/proxy-core/src/inbound/socks5.rs`, treat `Client → VLESS: EOF` / reset as a normal peer-close signal for the upload side, while still allowing the downstream VLESS → client path to drain until the client socket is actually gone.
- Keep `close_outbound_on_input_end` disabled for the SOCKS5 VLESS relay. `VlessStream.close()` sends a WebSocket Close for the entire tunnel, so calling it on Telegram upload EOF can race downstream delivery and trigger repeated native Telegram crashes in `Connection::onReceivedData()`.
- If a later VLESS → client write hits `Broken pipe`, `Connection reset`, `Connection aborted`, or `Not connected` after client EOF, treat it as an expected Telegram close path rather than a protocol failure.
- **Do not** close the entire tunnel early just because the client has stopped sending.

### WebSocket Connection Pacing

- Global WebSocket connect pacing caused starvation with Telegram's parallel connections.
- The fix: **Only retry attempts are paced**, not initial connections.
- In `VlessClient._connectWithRetry()`, the retry loop has delay, but initial connection does not.
- **Do not** add global pacing that delays all concurrent WebSocket connections.

### Hysteria2 First-Downstream Timing

- Hysteria2 reuses an authenticated QUIC connection, so new TCP streams can return data much faster than new VLESS WebSocket tunnels.
- Telegram 11.13.3 on affected Redmi devices can crash in `Connection::onReceivedData()` when the first Hysteria2 downstream bytes arrive during native connection initialization.
- Keep the protocol-specific first-downstream grace exposed by `ProxyStream::first_downstream_grace()`:
  - VLESS/default: `100ms`
  - Hysteria2: `350ms`
- Do not replace this with global connection pacing; only delay downstream reads after that SOCKS tunnel has forwarded its first real client payload.
- Hysteria2 streams must expose the concrete QUIC route IP and endpoint port through `local_bind_addr()` so SOCKS5 CONNECT replies do not fall back to the listener port.

### Address Fallback

- Telegram may connect to multiple addresses in parallel (IPv4/IPv6).
- WebSocket connection now falls back to the first resolved address if the preferred fails.
- **Do not** remove the fallback logic in `_connectToWebSocket()`.

### Hysteria2 IPv6 Target Formatting

- Hysteria2 TCP requests carry the destination as a host-and-port string. IPv6 literals MUST use bracketed authority form such as `[2001:67c:4e8:f002::a]:443`.
- Do not serialize an IPv6 destination as `2001:67c:4e8:f002::a:443`; Hysteria2 servers can interpret the final port as part of the IPv6 address and fall back to port `0`, returning `unsupported address`.
- Telegram probes IPv4 and IPv6 data-center addresses in parallel. Repeated IPv6 request rejection can amplify Telegram's native receive/reconnect race and trigger `Connection::onReceivedData()` crashes on affected builds.
- Related file: `rust/proxy-core/src/outbound/hysteria2.rs`.

### SOCKS5 CONNECT Reply/Data Boundary

- Telegram's native SOCKS5 client treats the entire `recv()` while waiting for the CONNECT reply as handshake data and does not preserve bytes following the reply.
- After sending and flushing the SOCKS5 CONNECT success reply, wait for the first client payload before starting downstream relay. Use a short timeout fallback so server-speaks-first protocols still work.
- Buffer that first client payload and forward it exactly once. For VLESS, pass it through the existing combined-handshake path so the VLESS request and first payload remain in one WebSocket frame.
- After forwarding a real first client payload, keep a short downstream-start grace period before reading upstream responses. Telegram 11.13.3 on affected Android devices can crash in `Connection::onReceivedData()` when the first encrypted response returns within roughly 20–50ms of SOCKS setup.
- Keep this grace limited to new SOCKS5 tunnel establishment; do not pace later relay chunks or globally serialize parallel Telegram connections.
- Do not replace this boundary with immediate concurrent downstream relay; kernel TCP coalescing can merge the CONNECT reply and Telegram's first encrypted downstream bytes, desynchronize MTProto, and trigger native `Connection::onReceivedData()` crashes.
- Related files: `rust/proxy-core/src/inbound/socks5.rs`, `rust/proxy-core/src/inbound/relay.rs`.

### Log Interpretation Pitfall

- Telegram opens many short-lived parallel SOCKS5 connections. Some of them are only probe/bootstrap channels and may close quickly after sending their initial payload.
- In logs, repeated `Client → VLESS: EOF` followed by a later downstream write failure on the same connection is not automatically a proxy regression; correlate it with connection duration and whether the client had already closed its input side.
- Focus on regressions where CONNECT replies are malformed, auth negotiation is wrong, or long-lived data channels collapse before Telegram finishes handshake/bootstrap.

## Build Size & Code Optimization Guidelines

## Git Artifact Hygiene

- Do **not** commit generated build artifacts or binary outputs unless the user explicitly requests it.
- In this repo, treat the following as local/CI-generated by default and keep them out of commits/history:
  - `rust/proxy-core/target/**`
  - `android/app/src/main/jniLibs/*/libproxy_core.so`
- If native binaries are needed for testing, build them locally or in CI and deliver them as artifacts instead of checking them into git.
- If binary files were accidentally tracked, remove them from the index/history on the working branch while preserving source changes.
- Before committing native/runtime changes, review `git diff --name-only` specifically for `target/`, `jniLibs/`, `.so`, `.a`, `.rlib`, and other generated outputs.

## Side-by-Side Profile Package

- The Android `profile` build uses `applicationIdSuffix = ".profile"`, producing `lightly.tool.profile`.
- Manifest permission names and provider authorities must derive from `${applicationId}` so profile and release packages can be installed together without provider conflicts.
- `EasyTierInfoProvider` must validate against the runtime package name via `EasyTierStateStore.authorityFor(context.packageName)` rather than a hardcoded release authority.
- Profile-only popup diagnostics may log URL scheme, length, and case-presence flags, but must not log full external URLs or sensitive payload tokens.

### Release Build Flags
Always use obfuscation and split debug info for release builds:
```bash
flutter build apk --release --obfuscate --split-debug-info=build/app/outputs/symbols
```
This reduces APK size by:
- `--obfuscate`: Minifies Dart code
- `--split-debug-info`: Separates debug symbols

Do **not** rely on `--split-per-abi` alone in this repo because checked-in `android/app/src/main/jniLibs/` can still leak extra ABI slices unless `TARGET_ABI` is also supplied to Gradle.

### Android Build Configuration
Enable minification and resource shrinking in `android/app/build.gradle.kts`:
```kotlin
release {
    isMinifyEnabled = true
    isShrinkResources = true
    proguardFiles(
        getDefaultProguardFile("proguard-android-optimize.txt"),
        "proguard-rules.pro"
    )
}
```

### Code Structure Best Practices
- Keep files under 400 lines when possible
- Extract large widget classes to standalone files (e.g., `PopupWebViewDialog`)
- Remove dead code promptly (unused widget classes, imports)
- Extract duplicate patterns to shared helpers (e.g., `_updateState()`)

### Performance Patterns Already in Use
- **Progress updates**: Use `ValueListenableBuilder` + throttling (5% threshold)
- **Scroll position**: Batch updates (24px delta threshold)
- **Address bar**: Self-managed state to avoid parent rebuilds
- **Video detection**: 180ms debounce on MutationObserver

## Tab Persistence Guidelines

- `BrowserTabService` is a global singleton; never instantiate it directly outside of `factory BrowserTabService()`.
- Tab sessions (URLs, titles, active index) are persisted to SharedPreferences automatically on app lifecycle pause and on `BrowserPage` dispose.
- When restoring sessions on launch, if no persisted data exists, fall back to creating a single favorites-page tab.
- Keep-alive objects are **not** serializable; they are recreated when tabs are rebuilt by the WebView host. Do not attempt to persist them.

## Service Auto-Start Guidelines

- On app launch, `BrowserPage._initialize` automatically starts:
  - Local HTTP file server (if enabled in settings, default port 3001)
  - Clipboard HTTP server (if enabled in storage, default port 12345)
  - Proxy (if configured and enabled)
- These services are singletons; calling `start()` while already running should gracefully restart (stop then start) to pick up new ports/paths.
- Clipboard server default: enabled, port 12345.
- HTTP file server default: enabled, port 3001.

## Drawer Navigation Guidelines

- The app drawer uses `Navigator.pushNamed()` (NOT `pushReplacementNamed`) for all internal routes.
- This keeps `BrowserPage` alive in the navigation stack so WebView tab state is not destroyed when switching to Clipboard / Settings / etc.
- The back button from any sub-page naturally returns to `BrowserPage`.

## Release Build (per-ABI packages)

From now on, Android releases for this project should prefer **separate 32-bit and 64-bit packages** instead of a universal mixed-ABI APK.

### Canonical build path

Use the checked-in script as the source of truth:

```bash
scripts/build_multi_abi.sh
```

That script is now responsible for all of the following:

- clearing old APK outputs
- exporting `TARGET_ABI` so Gradle filters packaged `jniLibs`
- applying `--obfuscate --split-debug-info=build/app/outputs/symbols`
- producing both:
  - `app-arm64-v8a-release.apk`
  - `app-armeabi-v7a-release.apk`
- passing `BUILD_VERSION_CODE` so Gradle uses `5000 + main-branch commit count` as the Android `versionCode`

Prefer the script over ad-hoc manual commands whenever both ABIs are needed.

Recommended commands:
```bash
# clear previous APK outputs first
rm -f build/app/outputs/flutter-apk/*

# arm64 release
TARGET_ABI=arm64-v8a flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/app/outputs/symbols

# preserve the arm64 artifact with an ABI-specific name before building the next one
cp build/app/outputs/flutter-apk/app-release.apk build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# arm32 release
GRADLE_OPTS="-Dorg.gradle.jvmargs='-Xmx12G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError'" _JAVA_OPTIONS='-Xmx12G' TARGET_ABI=armeabi-v7a flutter build apk --release --target-platform android-arm --obfuscate --split-debug-info=build/app/outputs/symbols

# preserve the arm32 artifact with an ABI-specific name
cp build/app/outputs/flutter-apk/app-release.apk build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
```

Important:
- Because Flutter still emits `app-release.apk`, the second build can overwrite the first unless you copy/rename it immediately.
- `TARGET_ABI` must use Android ABI names (`arm64-v8a`, `armeabi-v7a`), not Flutter platform names (`android-arm64`, `android-arm`).
- `--target-platform` and `TARGET_ABI` must be supplied together.
- `app-release.apk` may still be a mixed-ABI artifact if the build/pipeline is not filtering packaged `jniLibs` as expected.
- As of the current build flow, `android/app/build.gradle.kts` excludes sibling ARM and x86/x86_64 `.so` slices when `TARGET_ABI` is set. Verify this if packaging logic changes again.
- Treat explicitly generated per-ABI outputs / commands as the source of truth for release delivery.
- Do not assume `--target-platform android-arm64` alone guarantees a small single-ABI package when manual `jniLibs/` are checked in.

- The checked-in script uses conservative local build settings: Gradle daemon disabled, parallel disabled, limited workers, cleanup between ABIs, and a cooldown/memory snapshot between builds. Keep this behavior unless CI or the local host is known to tolerate faster settings.
- Clear Flutter incremental build state (`.dart_tool/flutter_build`) before the first ABI build and again between ABI builds. Stale depfiles or kernel snapshots can make a fresh-looking APK behave like older code even when the artifact timestamp and version label are new.
- When diagnosing release-package mismatches, have the script print APK manifest `versionName` / `versionCode` and a hash for each ABI artifact immediately after build, so the installed file can be matched to the produced output exactly.
- If script output says `Version Code: N`, verify Gradle actually used the same value when changing version wiring; the build script must pass `BUILD_VERSION_CODE` and `android/app/build.gradle.kts` must consume it.
- Keep the numeric version base as `5000 + main branch commit count`; the important invariant is counting `main` only, not the current feature branch, so branch-local commits do not inflate release `versionCode`.

### Semantic version label + Android versionCode

- Before any user-requested compile/build step, commit the current code first so the output APK can be traced back to an exact revision.
- User-facing build labels should use `vx.x.x+<6-digit commit id>` instead of `vx.x.x+<number>`.
- The commit-based build label already carries the leading `v`; do not prepend another `v` in UI display strings.
- Android `versionCode` for release packages should be **5000 + main branch commit count**, passed through `BUILD_VERSION_CODE` by `scripts/build_multi_abi.sh`.
- Keep the commit-based user-facing label separate from Android's numeric `versionCode`.
- Prefer supplying both the commit-based label and numeric versionCode at build time from git rather than editing `pubspec.yaml` for every package.
- If a test device has a higher temporary `versionCode` installed, Android will reject the main-count release as a downgrade; either uninstall after confirming data can be cleared, or intentionally build a temporary higher versionCode package outside the normal release rule.

### APK Installation Pitfall: Version Code Downgrade

Android **rejects** APK installation when the new APK's `versionCode` is lower than the currently installed version. This results in:
```
INSTALL_FAILED_VERSION_DOWNGRADE: Downgrade detected
```

**Handling:**
- Normal release builds use `5000 + main-branch commit count` as `versionCode`; do not count the current feature branch or all local commits by mistake.
- If you must reinstall a lower version, uninstall first only after confirming data can be cleared: `adb uninstall lightly.tool`.
- To check current device versionCode: `adb shell dumpsys package lightly.tool | grep versionCode`.
- Verify the built APK, when needed, with `apkanalyzer manifest print build/app/outputs/flutter-apk/app-arm64-v8a-release.apk | grep -E "versionCode|versionName"`.

**Also update AGENTS.md** with new guidelines when they emerge from real-world fixes.

## WebRTC Voice over EasyTier / Remote-Control Path

### Remote-control platform channel boundary

- Dart code must access the native `remote_control` MethodChannel through `RemoteControlPlatformGateway`; do not create additional raw `MethodChannel('remote_control')` instances in pages, widgets, or services.
- Keep video-frame forwarding as a direct typed gateway call with the original `Uint8List`; do not add JSON/base64 conversion, event-bus routing, or extra buffer copies on the screen hot path.
- `RemoteControlMessageRouter` and command helpers should depend on typed callbacks such as `executeCommand`, not on Flutter `MethodChannel` objects.
- Tests may mock `RemoteControlPlatformGateway.channelName` to verify the Android contract without bypassing the shared channel name.

Remote-control WebRTC voice has several real-world pitfalls that must not be regressed:

- The remote-control TCP connection is the source of truth for reachability.
  - When controller/receiver control and screen sockets are already connected through a host such as `10.126.*`, WebRTC should prefer that same proven remote-control IP instead of relying only on default Wi-Fi ICE candidates.
  - `RemoteControlVoiceCoordinator.handleIncomingWebRtcSignal()` passes the active remote-control target host into `WebRtcVoiceService.handleSignal()`. Keep this path intact.

- EasyTier / overlay sessions may not expose useful WebRTC host candidates automatically.
  - `WebRtcVoiceService` resolves the local `10.126.*` interface and `WebRtcCandidateFilter.rewriteHostCandidateIp()` rewrites host candidates to advertise that overlay IP when the remote target is also overlay-routed.
  - Do not remove candidate rewrite/logging unless EasyTier WebRTC voice is re-tested with both controller and receiver over `10.126.*`.

- Interpret audio logs carefully:
  - `AudioTrack ... [mute]` / `isLongTimeZeroData` with `MODE_IN_COMMUNICATION` and active playback means the Android output path is open but WebRTC is receiving silence or the peer connection is failed. It is not automatically a speaker-volume problem.
  - `FlutterWebRTCPlugin: onConnectionChangeFAILED` on either side usually points to ICE/candidate reachability, not microphone hardware.
  - Useful log filters: `webrtc-remote-audio`, `webrtc-local-candidate`, `webrtc-overlay-candidate-rewritten`, `webrtc-stats`, `onConnectionChange`, `AudioTrack`, `WebRtcAudioRecordExternal`.

- Receiver-side output volume is intentionally boosted modestly.
  - `WebRtcVoiceService` applies a bounded `Helper.setVolume(1.6, remoteTrack)` only when `_isController == false`, so the controlled device hears the controller louder without also amplifying controller-side monitoring and echo.
  - Keep this boost modest; large values can clip or increase echo on some phones.

- Internal proxy mode intentionally does not provide WebRTC voice.
  - Test WebRTC voice over LAN or EasyTier direct remote-control connections, not the internal proxy path.

Recommended verification after touching WebRTC voice:

```bash
flutter analyze lib/services/webrtc_voice_service.dart lib/services/remote_control_voice_coordinator.dart lib/services/remote_control_service.dart
flutter test test/services/webrtc_candidate_filter_test.dart test/services/remote_control_voice_coordinator_test.dart test/services/
```

Manual smoke test:

1. Connect remote control over LAN and verify two-way voice.
2. Connect remote control over EasyTier `10.126.*` and verify `onConnectionChangeCONNECTED` or equivalent stable audio behavior.
3. Confirm logs include overlay candidate rewrite when using EasyTier.
4. Confirm the controlled device output is louder but not clipped or echoing badly.

## Redmi / Qualcomm Remote-Control Black-Screen Pitfalls

Redmi / Qualcomm devices can fail remote screen display in two different places:

- **Receiver/capture side**: `MediaProjection` permission succeeds, `VirtualDisplay` is created, and the AVC encoder starts, but `ScreenCapture` emits zero output frames (`frames=0 keyFrames=0 lastEncodedAgo=-1ms`) even after repeated key-frame requests. Treat this as an encoder/VirtualDisplay stall, not a network failure. Keep the no-output fallback path in `android/app/src/main/kotlin/lightly/tool/ScreenCapture.kt` so the capture pipeline restarts with conservative codec settings and smaller capture sizes.
- **Controller/decode side**: Redmi's H.264 decoder may reject large remote sizes such as `1220x2712` during `MediaCodec.configure()`. Do not permanently fail the texture when initial decoder configuration throws; keep `H264Decoder` able to reconfigure after SPS/PPS arrives, using the stream's parsed dimensions.

Useful log markers:

- Capture-side stall: repeated `requestKeyFrame: hasCapture=true hasProjection=true` plus `Key frame requested: frames=0 keyFrames=0 lastEncodedAgo=-1ms`.
- Decode-side failure: `H264Decoder: Failed to configure decoder java.lang.IllegalArgumentException` immediately after `Created screen texture ... size=<large>`.

Recommended verification after touching this path:

```bash
./gradlew :app:compileDebugKotlin
flutter analyze lib/services/remote_control_service.dart lib/widgets/remote_control_screen_viewer.dart lib/pages/remote_control_session_page.dart
```

Manual smoke test on Redmi:

1. Redmi as receiver: start remote control, connect from another device, confirm the first visible frame appears and logs show either normal first frame or fallback restart followed by encoded frames.
2. Redmi as controller: connect to a high-resolution receiver and confirm `H264Decoder` configures after SPS/PPS and renders decoded frames instead of staying black.
3. Confirm touch gestures still execute while video is visible.

## Cloudflare-Challenged Site Compatibility

Some sites (e.g., `example-site.com`) use Cloudflare challenge/bot detection that fails when accessed through certain proxy/VLESS paths due to:
- TLS fingerprint mismatches in non-browser TLS stacks
- IP reputation checks on proxy egress
- Missing browser-like signals (cookies, JA3/JA4 fingerprints)

### Built-in proxy bypass for affected sites

The browser maintains a built-in bypass list in `BrowserSettings._builtInProxyBypassDomains` that includes:
- `google.com`, `gstatic.com`, `googleapis.com` (for Google auth flows)
- `example-site.com` (Cloudflare challenge compatibility)
- `challenges.cloudflare.com` (challenge platform direct access)

**Do not remove** these bypass entries without verifying the sites work through the full proxy path.

### Guidelines for adding new bypass entries

When a site consistently returns "You don't have permission" or Cloudflare challenge failures through the proxy path:

1. First verify it's a Cloudflare challenge by checking for interstitial pages
2. Add the domain to `_builtInProxyBypassDomains` in `lib/browser/browser_settings.dart`
3. Add corresponding tests in `test/browser/browser_settings_test.dart`
4. Document in `AGENTS.md` or permanent docs with verification steps

## WebView HTTP Auth & Popup Compatibility

### Manual refresh must recover stalled white pages

- The address-bar refresh action must not only call `stopLoading()` while a page is loading. It must stop the stalled request and immediately navigate to the current real page URL again.
- Prefer the controller URL when it is a real document URL, but fall back to the active tab URL for `about:blank`, `chrome-error://`, missing URLs, or controller read failures.
- Send no-cache request headers for this explicit recovery action. If the native controller is unavailable or navigation throws, recreate the active tab keepAlive as a recovery path.
- Keep this behavior limited to explicit user refresh; do not add automatic reload loops for normal page errors.
- Related files: `lib/browser/services/browser_force_refresh_coordinator.dart`, `lib/pages/browser_page.dart`.

### Runtime browser diagnostics must remain useful and lightweight

- When runtime logging is enabled, record low-frequency WebView lifecycle markers: main-page load start/stop with elapsed time, main-frame resource/HTTP errors, renderer process exit, and explicit force-refresh attempts.
- Do not log progress ticks, scroll callbacks, subresource failures, full query strings, fragments, or custom-scheme payloads. These can create performance regressions or expose sensitive tokens.
- Serialize runtime log file appends and wait for pending writes before reading/exporting, otherwise multiple unawaited events can race or the exported file can miss the latest entries.
- Disabling runtime logging must stop accepting new entries, wait for queued writes, and delete `runtime.log` from the app external `logs` directory. Re-enabling starts a new diagnostic session and recreates the file with the new enable marker. Normal app startup with logging already enabled must not clear the existing session.
- Related files: `lib/browser/services/browser_webview_diagnostics.dart`, `lib/services/app_log_service.dart`, `lib/browser/widgets/browser_webview_host.dart`.

### Proxy-core diagnostic release logging

- Release builds default proxy-core logging to `warn` to avoid normal connection-lifecycle noise.
- For a targeted diagnostic APK, pass `--dart-define=PROXY_CORE_LOG_LEVEL=info`; do not change the permanent release default to `info`.
- Info-level proxy logs may include destination IP/domain, ports, byte counts, and connection lifecycle, but must not include proxy credentials, configuration bodies, or packet contents.
- Native startup logging must report only the listen address, protocol name, and configuration length. Never log the raw proxy JSON because it contains UUIDs/passwords.
- Related file: `lib/browser/services/proxy_runtime_launcher.dart`.

### Application runtime logging boundaries

- Important Release-mode failures must use `recordRuntimeLog()` so they remain visible in both developer output and the exportable runtime log. This includes proxy-core lifecycle failures, EasyTier start/stop errors, remote-control connection lifecycle failures, screen capture/decoder setup failures, local HTTP service request failures, backup errors, and external-app launch exceptions.
- Keep per-frame screen data, gesture coordinates, WebView progress/scroll events, EasyTier network-info polling, and other hot-path diagnostics console-only. Persisting them can create I/O jank and oversized logs.
- Persist only bounded metadata. Do not write proxy credentials/config bodies, cookie values, URL query strings/fragments, custom-scheme payloads, video stream URLs, clipboard contents, or file contents.
- Sanitize runtime-log messages, errors, stack traces, and nested metadata centrally before file writes. Platform exceptions must omit native `details`, sensitive metadata keys must be redacted, and URL logging must remove query/fragment data or redact custom-scheme payloads.
- For errors that can repeat on every frame, persist the first consecutive failure and keep subsequent repeats console-only until a successful operation resets the failure state.
- Related files: `lib/services/app_log_service.dart`, `lib/services/proxy_core_service.dart`, `lib/services/easytier_service.dart`, `lib/services/remote_control_service.dart`, `lib/widgets/remote_control_screen_viewer.dart`.

### Low-risk service and settings boundaries

- Keep runtime-log file/session management in `AppLogService` and all recursive redaction rules in `RuntimeLogSanitizer`; do not grow the file service with URL or metadata sanitization branches again.
- Keep `SimpleFileManagerService` limited to settings, server lifecycle, root binding, and state notifications. HTTP routing/file operations belong in `SimpleFileManagerRequestHandler`, while the embedded browser UI belongs in `simple_file_manager_web_ui.dart`.
- Keep proxy protocol field-reset rules in `BrowserProxyFormMutator`. `SettingsPage` should coordinate `setState`, dirty state, snackbars, and async actions rather than duplicating protocol-specific form mutation rules.
- Related files: `lib/services/runtime_log_sanitizer.dart`, `lib/services/simple_file_manager_service.dart`, `lib/services/simple_file_manager_request_handler.dart`, `lib/browser/services/browser_proxy_form_mutator.dart`, `lib/pages/settings_page.dart`.

### Percent-encoded popup URLs must be decoded before routing

- Some pages pass an entire custom-scheme popup target as a percent-encoded string, for example `baiduboxapp%3A%2F%2F...`.
- Decode valid percent-encoded popup URLs before scheme detection, suppression checks, confirmation display, external-app launching, or nested popup creation.
- Dart `Uri.toString()` can percent-encode a decoded custom-scheme payload again (for example `bankabc://{"method":...}`), so external-app confirmation dialogs must decode their final display string after URI conversion; keep the launch `Uri` unchanged.
- Custom-scheme payloads placed directly after `//` are parsed as URI authority/host data, so normal `Uri.toString()` serialization can lowercase case-sensitive payload fields. The shared external URL launcher must prefer `WebUri.rawValue`, restore known case-sensitive payload keys, and launch with `forceToStringRawValue: true`; do not limit this protection to `onCreateWindow`, because direct navigation/error/history callbacks can launch the same URL.
- Custom schemes with an encoded JSON authority, such as `bankabc://%7B%22method%22...%7D`, are not valid after full decoding (`Uri.tryParse` can reject the JSON colon as an invalid port). Detect the scheme from decoded text, but preserve the WebView `WebUri.rawValue` for Android external-app launch.
- Do not pass these raw custom-scheme strings through `Uri.parse`: Dart treats the encoded payload after `//` as a host and lowercases case-sensitive JSON values/keys such as `jumpToSharedProduct` and `trafficTag`. Launch with `WebUri(rawUrl, forceToStringRawValue: true)` so Android receives the exact original string.
- Android WebView may normalize/lowercase an encoded custom-scheme authority before `onCreateWindow`. Keep the document-start raw-popup capture script enabled so original `window.open()` arguments and anchor `href` attributes can be recovered before Chromium normalization; use the captured value ahead of the callback URL.
- The capture script also reports raw URLs through the `lightlyRawPopupUrlCaptured` JavaScript handler so cross-origin iframe captures reach Dart. Keep the `onLoadStart` reinjection fallback because some Android WebView versions or child windows do not reliably install document-start scripts.
- As a final compatibility fallback for the verified `bankabc` protocol, restore the known case-sensitive payload tokens `jumpToSharedProduct` and `trafficTag` if Chromium has already lowercased them before any capture path can observe the original value.
- Keep malformed percent encoding unchanged instead of throwing and breaking the WebView popup callback.
- Apply the same normalization to both main WebView popups and nested popup WebViews.
- Related files:
  - `lib/browser/utils/browser_popup_url_decoder.dart`
  - `lib/browser/services/browser_popup_window_handler.dart`
  - `lib/browser/widgets/popup_webview_dialog.dart`
- Verification: trigger an encoded `baiduboxapp://v1/easy/bydird?upgrade=1&type=hybird` popup and confirm the decoded URL is shown and routed as an external app URL.

### HTTP auth dialogs must be handled explicitly

- `flutter_inappwebview` 6.1.5 does **not** show a native HTTP auth dialog automatically.
- If `onReceivedHttpAuthRequest` is unhandled, the request is effectively canceled and the page can fail with `ERR_HTTP_RESPONSE_CODE_FAILURE`.
- Both the main browser WebView and popup WebViews must handle `onReceivedHttpAuthRequest` and return `HttpAuthResponse(action: HttpAuthResponseAction.PROCEED)` after prompting for credentials.
- Related files:
  - `lib/browser/widgets/browser_webview_host.dart`
  - `lib/pages/browser_page.dart`
  - `lib/browser/widgets/popup_webview_dialog.dart`
- Verification:
  - open an HTTP-auth protected page such as `http://192.168.1.76:5032`
  - confirm the username/password dialog appears in the normal browser flow

### Deferred auth popups must not be globally suppressed

- Some login providers, including Telegram / OAuth-style flows, create a popup window with an empty URL first and navigate it later.
- Do **not** suppress every empty `onCreateWindow` request globally, or login buttons can appear to do nothing.
- Allow deferred empty popups only when all of these are true:
  - there is a user gesture
  - the current/source URL looks like an auth flow (`login`, `signin`, `oauth`, `authorize`, `auth`, `telegram`)
- Keep generic empty/image popup suppression for non-auth flows to avoid linux.do avatar/image popup storms.
- `example-site.com` challenge/login flow should bypass the in-app proxy path by default, together with `challenges.cloudflare.com`, because the proxied WebView/VLESS route can trigger Cloudflare forbidden/challenge failures before auth completes.
- Related files:
  - `lib/pages/browser_page.dart`
  - `lib/browser/widgets/popup_webview_dialog.dart`
- Verification:
  - from `https://example-site.com/login`, tapping the Telegram button should open the auth popup
  - linux.do avatar/image links should remain suppressed

## X / YouTube WebView Mobile Layout Compatibility

- `x.com` / `twitter.com` and `youtube.com` / `youtu.be` should prefer the mobile WebView layout in this app.
- Keep the browser mobile-mode WebView policy using the mobile user agent, and disable `useWideViewPort` plus `loadWithOverviewMode`. The wide/desktop-style viewport path can make responsive sites keep desktop-style UI even after switching to mobile mode; it also makes X / YouTube internal bottom navigation areas render with excessive blank height in fullscreen.
- There is also a site-specific compatibility CSS injection path (`BrowserSiteCompatibilityScript`) used to clamp the internal bottom navigation height for X and YouTube after load. Re-test these hosts before removing it.
- Browser desktop/mobile mode switching must force the current page to reload with the new WebView settings, not only save settings or rebuild Flutter widgets. Many sites choose mobile/desktop UI from the navigation request user-agent, WebView content mode, viewport width, and JavaScript environment signals, so changing state without a new request can leave the visible page unchanged.
- Runtime `InAppWebViewController.setSettings()` is not reliable enough for this mode switch on all Android WebView paths. Prefer recreating retained WebViews / keepAlives so the next native WebView is created with the correct user agent, `preferredContentMode`, `useWideViewPort`, and `loadWithOverviewMode`.
- The More-sheet toggle should flip from BrowserPage's current in-memory setting, not only the latest persisted setting, otherwise a stale page state can make the button appear to do nothing or switch the wrong way.
- Custom desktop UA is a desktop-mode-only override from Settings → General. Keep mobile mode on the built-in mobile UA unless X / YouTube are re-tested.
- Desktop mode compatibility should be generic for all web URLs, not a growing list of site-specific branches. Keep the desktop-only `BrowserSiteCompatibilityScript.desktopViewportOverrideForUrl()` injection at WebView creation/load-stop, and make it present a desktop UA, desktop-width viewport, non-mobile UA-CH (`navigator.userAgentData.mobile=false`), desktop screen dimensions, non-touch `maxTouchPoints`, and desktop-like `matchMedia` results. Do not apply it in mobile mode.
- When switching to desktop mode, normalize `m.youtube.com` URLs to `www.youtube.com`; do not add the reverse rewrite for mobile mode unless YouTube mobile layout and native parser flows are re-tested.
- Related files:
  - `lib/browser/widgets/browser_webview_host.dart`
  - `lib/browser/utils/browser_site_compatibility_script.dart`
  - `lib/browser/utils/browser_url_utils.dart`
  - `lib/pages/browser_page.dart`
  - `lib/pages/settings_page.dart`
  - `lib/browser/services/browser_tab_service.dart`

## Selective Browsing Data Clearing

The browser supports clearing different categories of data independently:

### Available categories
- **History**: Browsing history + address bar suggestions (clears `BrowserSuggestionService` cache)
- **Cookies & Site Data**: `CookieManager.deleteAllCookies()` + `WebStorageManager.deleteAllData()`
- **WebView Cache**: Global cache via `InAppWebViewController.clearAllCache()`
- **Download Records**: Database records only (files preserved)
- **Favorites**: All bookmark entries
- **Clipboard**: Stored clipboard content
- **Calculator History**: Calculator expression history

### Cookie export origin tracking

- Android WebView does not provide a supported full-cookie enumeration API in the current `flutter_inappwebview` Android implementation.
- Do not derive cookie export targets from browsing history; users can clear history while cookies remain, causing `session` cookies to be skipped.
- Cookie export should use the independent WebView cookie-origin index maintained from real WebView navigation events, plus documented supplemental origins, before calling `CookieManager.getCookies(url)`.
- Clearing cookies/site data should clear this origin index; clearing history alone should not.

### App cache maintenance

Device app-cache buildup can make the in-app browser visibly lag or fail to open pages. Keep the Settings → General "清理应用缓存" action and scheduled cleanup path working.

- App-cache cleanup should clear WebView cache, Flutter image cache, the app cache directory, and temporary-directory children.
- It must not be conflated with browsing-data clearing categories such as history, favorites, download records, clipboard, calculator history, or persisted settings.
- Automatic cleanup should run opportunistically from browser startup and must not block startup if cleanup fails.
- Proxy node speed testing in Settings → Proxy must remain cancelable; the button should switch to "关闭测速" while a probe is active and cancel the active probe without saving settings.
- Related files:
  - `lib/services/app_cache_maintenance_service.dart`
  - `lib/pages/settings_page.dart`
  - `lib/browser/services/proxy_latency_probe.dart`
  - `lib/browser/services/proxy_latency_tester.dart`
- Verification:
  - `flutter test test/services/app_cache_maintenance_service_test.dart test/browser/proxy_settings_section_test.dart`

### Important: Favorite status tracker cache invalidation

When clearing favorites from Settings, `BrowserFavoriteStatusTracker` maintains an in-memory `_statusCache` that can become stale. Always:

1. Call `favoriteStatusTracker.clearCache()` after favorites are cleared
2. Or trigger `refreshStatus()` on returning to BrowserPage
3. Set `_hasAppliedChanges = true` in SettingsPage so BrowserPage reloads settings on return

**File**: `lib/browser/services/browser_favorite_status_tracker.dart`

## Settings → BrowserPage State Refresh Pattern

When SettingsPage makes changes that affect BrowserPage's live state:

1. Set `_hasAppliedChanges = true` after the operation succeeds
2. On Navigator.pop, this triggers `_reloadSettings()` in BrowserPage
3. `_reloadSettings()` calls `replaceSuggestionService()` to reset caches
4. For favorites, explicitly call `favoriteStatusTracker.refreshStatus()` after reload

**Do not** forget to set `_hasAppliedChanges` or BrowserPage will use stale cached data.

## Lock Icon Site-Data Clearing Dialog

The address bar lock icon opens a dialog for clearing current-site data:

### UX Requirements
- **Button label**: "清除该网站数据" (NOT "清除缓存" - be accurate about what gets cleared)
- **Confirmation text**: Explicitly state "不包含 WebView 全局缓存"
- **Success message**: "已清除 ${host} 的 Cookie 与站点数据（不含全局缓存）"

### Technical implementation
- Clears cookies for specific URL/domain via `CookieManager.deleteCookies()`
- Clears localStorage/sessionStorage via injected JavaScript
- Clears Cache API and IndexedDB via JavaScript
- Calls `controller.webStorage.localStorage.clear()` and `sessionStorage.clear()`
- On Android: calls `WebStorageManager.deleteOrigin()` for the origin
- **Does NOT clear** global HTTP cache (WebView limitation)

**Files**: `lib/pages/browser_page.dart` (`_showSiteSecurityDialog`, `_clearCurrentSiteData`)

## EasyTier Android Integration Notes

- EasyTier Android integration in this repo uses:
  - Flutter UI / MethodChannel
  - Kotlin JNI wrapper
  - Rust `easytier-android-jni` + `easytier_ffi`
  - Android `VpnService` for TUN handoff

### Native linking pitfall

- `libeasytier_android_jni.so` depends on symbols exported by `libeasytier_ffi.so`.
- Do **not** rely only on `System.loadLibrary("easytier_ffi")` ordering.
- Keep the Rust-side explicit dylib link so the built JNI library carries `DT_NEEDED: libeasytier_ffi.so`.
- If you see:
  - `UnsatisfiedLinkError: cannot locate symbol collect_network_infos`
  check the JNI binary dependency chain first.

### Library provenance rule

- This Flutter repo ships the EasyTier native runtime by checking compiled `.so` files into:
  - `android/app/src/main/jniLibs/arm64-v8a/`
  - `android/app/src/main/jniLibs/armeabi-v7a/`
- The Rust source of truth still lives in the separate EasyTier repo at:
  - `/home/easul/workspace/EasyTier`
- Keep in mind:
  - changes made in the EasyTier source repo are **not** automatically versioned in this Flutter repo
  - the Flutter app only uses whatever compiled JNI/FFI artifacts were copied into `jniLibs/`
- If behavior changes after rebuilding EasyTier, verify that the freshly built `.so` files were actually copied into this repo before testing or committing.

### Config schema pitfall

- Follow `easytier/src/common/config.rs` (`TomlConfigLoader`) as the source of truth.
- Valid structure for this project is:
  - top-level: `instance_name`, `hostname`, `ipv4` / `dhcp`, `listeners`, `socks5_proxy`
  - `[network_identity]`: `network_name`, `network_secret`
  - `[[peer]]`: `uri = ...`
  - `[flags]`: e.g. `disable_p2p = false`
- Do **not** place `hostname` or `ipv4` under `[network_identity]`.
- In TOML, keys after `[[peer]]` belong to that peer table until another table starts.
  - Keep all top-level EasyTier keys, especially `listeners` and `socks5_proxy`, before any `[[peer]]` or `[[port_forward]]` section.
  - If `socks5_proxy` is emitted after `[[peer]]`, EasyTier starts normally but the no-tun SOCKS5 portal will not listen, causing controller no-VPN connections to fail with local `127.0.0.1:<port>` connection refused.

### Mobile runtime pitfall

- On mobile, `runNetworkInstance()` returning success only means the instance started.
- It does **not** guarantee:
  - peer route synchronization finished
  - `my_node_info.virtual_ipv4` exists
  - `VpnService` should already start
- Keep the current monitor loop in `MainActivity.kt` that polls `collectNetworkInfos()` and only starts `EasyTierVpnService` after `virtual_ipv4` becomes available.
- Also note: when `virtual_ipv4` becomes available, the Android `VpnService` must add the **EasyTier virtual subnet route itself** (for example `10.126.126.22/24`) in addition to any `proxy_cidrs`, otherwise Android 7 can bring up `tun0` and assign the address but still fail to route peer traffic correctly.

### Mobile DHCP caveat

- Peer discovery can work while `virtual_ipv4` remains null.
- When debugging mobile EasyTier issues, static IPv4 in the already-discovered subnet is often more reliable than DHCP.

### Recommended verification when touching EasyTier code

- Build release APK:
  - `flutter build apk --release --target-platform android-arm64`
- Optional 32-bit build:
  - ensure both `libeasytier_android_jni.so` and `libeasytier_ffi.so` exist under `android/app/src/main/jniLibs/armeabi-v7a/`
  - then build with `flutter build apk --release --target-platform android-arm`
- Verify on-device:
  - VPN permission dialog appears
  - EasyTier no longer crashes on startup
  - `adb logcat -s EasyTier` shows monitor ticks and raw network info when needed
  - static hostname / static IPv4 appear in runtime network info

### 32-bit Android build pitfall

- arm32 support in this repo requires copying **both** EasyTier shared libraries into:
  - `android/app/src/main/jniLibs/armeabi-v7a/libeasytier_android_jni.so`
  - `android/app/src/main/jniLibs/armeabi-v7a/libeasytier_ffi.so`
- If only the JNI library is present, the 32-bit app may build incorrectly or fail at runtime due to missing FFI dependency.
- Release arm32 builds may fail during R8 minification with:
  - `java.lang.OutOfMemoryError: Java heap space`
- Prefer a staged fallback strategy for arm32 release builds:
  1. First try a moderate heap to avoid over-allocating memory unnecessarily:
     - `export GRADLE_OPTS="-Dorg.gradle.jvmargs='-Xmx4G -XX:MaxMetaspaceSize=512m'"`
     - `flutter build apk --release --target-platform android-arm`
     - `unset GRADLE_OPTS`
  2. If the build still fails in R8 with `Java heap space`, retry with the larger known-good workaround:
     - `GRADLE_OPTS="-Dorg.gradle.jvmargs='-Xmx12G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError'" _JAVA_OPTIONS='-Xmx12G' flutter build apk --release --target-platform android-arm`
- If the second ABI build fails because the Gradle daemon disappears after a successful arm64 build, stop daemons and retry arm32 with no daemon:
  - `cd android && ./gradlew --stop`
  - `GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.jvmargs='-Xmx12G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError'" _JAVA_OPTIONS='-Xmx12G' TARGET_ABI=armeabi-v7a flutter build apk --release --target-platform android-arm --obfuscate --split-debug-info=build/app/outputs/symbols`
- `scripts/build_multi_abi.sh` should keep the fast daemon-backed arm32 attempt first, but automatically fall back to `gradlew --stop` + no-daemon arm32 retry when that daemon-disappeared failure happens.
- In practice, prefer no extra heap tuning for arm64 unless the build actually shows memory pressure; this staged fallback is primarily for arm32 release packaging.

### Current open follow-up areas

- Persist EasyTier profiles across app restarts
- Support multiple EasyTier network profiles with quick switching
- Expose local app services over EasyTier-assigned IP
- Improve peer/device list presentation in the UI

### EasyTier UI / navigation notes

- The EasyTier / P2P entry now lives inside `SettingsPage`, not the global app drawer.
- Keep navigation consistent with the rest of the app settings structure:
  - drawer -> Settings
  - Settings -> `P2P VPN`
- If moving EasyTier entry again, prefer keeping it near other infrastructure features (proxy / local HTTP), not as a top-level drawer destination.

### EasyTier runtime JSON pitfall

- `EasyTierJNI.collectNetworkInfos()` returns a top-level object with a `map` field keyed by instance name.
- UI code must extract the current instance first (`map[instanceName]`) before reading:
  - `my_node_info`
  - `routes`
  - `events`
- A previous bug read `routes` and `my_node_info` from the top-level object directly, which made:
  - peer list appear empty
  - EasyTier IP appear missing
  - auto-refresh look broken even though polling was running
- Also, if users need to copy diagnostics, prefer preserving the raw JSON string returned by `collectNetworkInfos()` and formatting it with a JSON encoder; avoid relying on Dart `Map.toString()` for export/copy because it is harder to read and can appear truncated or structurally ambiguous.

### EasyTier state sharing for Monitor app

- Lightly exposes current EasyTier runtime state through a signature-permission protected Android ContentProvider so the separate monitor app can reuse Lightly's active P2P VPN instead of starting a conflicting VPN.
- Provider URI: `content://lightly.tool.easytier/network_info`.
- Caller permission: `lightly.tool.permission.READ_EASYTIER_STATE` with `signature` protection level. The monitor app must request this permission and be signed with the same certificate as Lightly.
- Returned columns:
  - `instance_name`
  - `raw_network_info_json`
  - `virtual_ipv4`
  - `updated_at`
  - `is_running`
  - `error_message`
- Treat `raw_network_info_json` as the source of truth; it is the raw `EasyTierJNI.collectNetworkInfos(10)` JSON and should remain compatible with `EasyTierNetworkInfoAnalyzer`.
- Related files:
  - `android/app/src/main/AndroidManifest.xml`
  - `android/app/src/main/kotlin/lightly/tool/EasyTierInfoProvider.kt`
  - `android/app/src/main/kotlin/lightly/tool/EasyTierStateStore.kt`
  - `android/app/src/main/kotlin/lightly/tool/MainActivity.kt`

### EasyTier local service exposure pitfall

- If local app services should be reachable over EasyTier IP, do not exclude the whole app from VPN routing with `addDisallowedApplication(...)`.
- Also note that Dart `HttpServer.bind(..., shared: false)` may behave poorly in multi-interface mobile VPN scenarios.
- P2P VPN supports the same no-VPN / no-tun mode as the remote-control receiver. When that mode is enabled from P2P settings, start EasyTier with `no_tun = true` and without Android `VpnService`; remote-control controller UI should only show a hint and continue connecting through the same non-VPN path.
- If the P2P no-tun instance is already running and the receiver also starts in no-VPN mode, reuse the existing EasyTier instance instead of stopping/restarting it.
- For no-tun exposure of non-Lightly services, use the structured port-mapping list in P2P settings. Each entry emits a same-port EasyTier `port_forward` rule like `tcp://0.0.0.0:<port>/127.0.0.1:<port>` and preserves the user's remark/name for UI only.
- Do **not** add receiver-side default remote-control `port_forward` rules to generic P2P no-tun startup. The receiver's Dart `ServerSocket` owns the actual remote-control ports; if EasyTier also binds `0.0.0.0:18080+`, receiver startup can fail with `Address already in use` and P2P no-tun can become unstable.
- P2P no-tun startup must not include user port mappings in the core EasyTier config. A local service may already own the same port (for example `18080`), and an EasyTier `port_forward` bind failure can prevent the entire P2P network from starting or refreshing peers.
- For remote-control controller connections in no-tun mode, normal Dart sockets cannot route `10.126.*` directly because Android has no VPN route. Use the EasyTier no-tun SOCKS5 portal (`127.0.0.1:11080` by default) for port probing and for both control/screen sockets. Do not restart the EasyTier no-tun instance merely to add controller-side `port_forward` rules, because that drops peer/device state and can leave the native instance alive while Dart UI returns to a stopped state.
- For this repo:
  - local HTTP file server should bind `0.0.0.0` when VPN/LAN exposure is desired
  - clipboard server should use `shared: true`
  - if a service is reachable from the host phone via EasyTier IP but not from a peer, first compare its binding mode against a known-good service (for example Termux or the local HTTP file server)
  - after EasyTier obtains a `virtual_ipv4`, in-app services may need to be restarted so they rebind in the post-VPN network environment, especially on Android 7

### EasyTier VPN stop lifecycle pitfall

- `stopService()` alone is not always enough to clear the Android system VPN indicator reliably.
- Keep the explicit `ACTION_STOP` path inside `EasyTierVpnService`, let the service close its own `ParcelFileDescriptor`, and rely on `stopSelf()` / `onRevoke()` for cleanup.
- Avoid immediately killing the service from `MainActivity` before the service has a chance to close the VPN interface itself, or the system VPN icon can linger.

### Android 7 / Android 10 service asymmetry note

- We observed a real-world case where one device could reach the peer's clipboard service over EasyTier but the reverse direction did not work.
- The first concrete checks for this repo should be:
  1. confirm the app is not excluded from VPN routing
  2. confirm the in-app HTTP server uses `shared: true`
  3. compare against a known-good server on the same device (for example Termux on port 8080)
- If the asymmetry persists after those checks, treat it as an Android-version-specific routing/interface issue and inspect runtime interface enumeration and post-VPN service restart timing before changing higher-level UI logic.

### EasyTier peer list UI pitfall

- Peer URIs can be long enough to overflow narrow mobile layouts.
- Keep peer rows bounded with ellipsis and preserve a selectable full-text view when needed.

## Native Video Parser Setting

- The YouTube/native-player parser endpoint is user-configurable via `BrowserSettings.nativeVideoParserApiBaseUrl`.
- Default parser endpoint: `https://parser.example.com`
- If the parser input is empty, YouTube links must **not** trigger native-player/floating parse behavior even when the native video player switch is enabled.
- Parser responses may include `title` alongside `urls`; keep that title visible in parsed video UI and use it as the initial download filename while preserving existing ellipsis and filename sanitization rules.
- This setting is part of the normal settings JSON, so backup export/import automatically persists it.

## Local HTTP / Clipboard LAN Address Display

- The local HTTP file service default root path is the shared Download directory: `/storage/emulated/0/Download`.
- When services are reachable over private IPv4 addresses, display concrete LAN URLs (`192.168.x.x`, `10.x.x.x`, `172.16-31.x.x`) instead of only `0.0.0.0`.
- Files:
  - `lib/browser/local_http_file_server_service.dart`
  - `lib/browser/clipboard_http_server_service.dart`
  - `lib/pages/settings_page.dart`
  - `lib/pages/clipboard_page.dart`

## Export / Download Directory Rules

- User-facing data exports should use the shared Android Download directory when available, with `/storage/emulated/0/Download` treated as the fixed primary path on Android.
- Keep backup export and runtime log export aligned to the same Download-directory rule to avoid sending files into app-private storage unexpectedly.
- Shared Download writes on Android must go through the existing file-access permission flow first.
- If the user denies access or the shared directory is unavailable, automatically fall back to an app-writable directory and surface the actual saved path in the UI.
- Related files:
  - `lib/browser/services/browser_backup_service.dart`
  - `lib/services/app_log_service.dart`
  - `lib/pages/data_management_page.dart`
- Verification:
  - trigger backup export and log export on Android
  - confirm the success toast / file path points into `/storage/emulated/0/Download` when shared storage is available

## Calculator Input / Compact Layout Rules

- Calculator keypad input must insert at the current cursor position and respect selected text ranges.
- Backspace must delete the selected range, or the character immediately before the caret when nothing is selected.
- Full-width Chinese parentheses `（ ）` must be normalized to ASCII `()` before evaluation.
- On short screens/small windows, the calculator body must remain scrollable/adaptive so the bottom keypad row is never pushed off-screen after showing results.

## Scope discipline

- Keep the browser lightweight.
- Do not add VPN-mode assumptions.
- When fixing the openai/workers-style node, always verify that the visa ws-tls node still works before declaring completion.
- When fixing Telegram compatibility, verify SOCKS5 still works with curl/Termux.

## Common Production Fixes (v1.0.1+2)

### 1. Completer "Future already completed" Error

**Error**: `Bad state: Future already completed`

**Cause**: `BrowserSuggestionService.dispose()` calls `complete()` without checking if already completed, especially when rapid focus changes or multiple disposals occur.

**Fix**: Always check `isCompleted` before calling `complete()` and clear references:
```dart
void dispose() {
  _debounceTimer?.cancel();
  if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
    _pendingCompleter!.complete(<BrowserSuggestion>[]);
  }
  _pendingCompleter = null;
  _lastIssuedQuery = null;
}
```

**File**: `lib/browser/services/browser_suggestion_service.dart`

## Browser History UI and Storage

- The Settings home page must show `历史浏览` as an independent row directly below `通用`; do not move it inside the General detail page.
- Address-bar history suggestions are structured title + URL rows. Matching covers both fields, while tapping always submits the stored URL rather than the visible title.
- Keep URL summary data in `browser_history` for suggestion ranking and per-visit data in `browser_history_visits` for the date-grouped history page.
- History-page navigation must return the selected URL through Settings to `BrowserPage`, which opens it with the existing new-tab path. The history page must not manipulate WebView keepAlive or tab services directly.
- Only normal `http` and `https` main-page visits should be recorded; skip internal, blank, custom-scheme, file, and content URLs.
- Related files: `lib/browser/services/browser_history_service.dart`, `lib/browser/services/browser_suggestion_service.dart`, `lib/pages/browser_history_page.dart`, `lib/pages/settings_page_home_sections.dart`.
- Verification: run `flutter test test/browser/browser_address_bar_test.dart test/browser/browser_history_page_test.dart test/browser/browser_suggestion_service_test.dart test/browser/browser_history_recorder_test.dart`.

### 2. Android Shared Downloads Write Permission

**Error**: `PathAccessException: Cannot open file, path = '/storage/emulated/0/Download/...' (OS Error: Permission denied)`

**Cause**: Android 10+ requires `WRITE_EXTERNAL_STORAGE` permission (not just read), and some ROMs restrict access even with permission granted. The app needs to verify actual write capability.

**Fix**: 
- Add `WRITE_EXTERNAL_STORAGE` to `AndroidManifest.xml` (maxSdkVersion="29")
- Check both read AND write permissions in `MainActivity.kt`
- Implement `_isDirectoryWritable()` test that creates/deletes a temp file to verify actual write access
- Fall back to app private directory if shared Downloads is not writable

**Files**: 
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/.../MainActivity.kt`
- `lib/services/shared_downloads_directory_service.dart`

### 3. VLESS "Broken pipe" Socket Error

**Error**: `SocketException: Write failed (OS Error: Broken pipe, errno = 32)`

**Cause**: Writing to a socket after the peer has closed the connection, or writing to `IOSink` after it's closed.

**Fix**: Add state tracking and exception handling:
- Add `outgoingClosed` flag to track stream state
- Wrap all socket writes in try-catch blocks
- Check `outgoingClosed` before writing
- Catch `SocketException` and handle gracefully without propagating

**Pattern**:
```dart
var outgoingClosed = false;

// In data handler:
try {
  if (!outgoingClosed) {
    outgoing.add(payload);
  }
} on SocketException {
  outgoingClosed = true;
}

// In onDone/onError handlers:
if (!outgoingClosed) {
  outgoingClosed = true;
  unawaited(outgoing.close().catchError((_) {}));
}
```

**File**: `lib/browser/vless_client.dart` (in `pipeBroadcast` and `_pipeWebSocket`)
