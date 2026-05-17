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
  - `## WebView HTTP Auth & Popup Compatibility`
  - `## Selective Browsing Data Clearing`
  - `## Settings → BrowserPage State Refresh Pattern`
  - `## Lock Icon Site-Data Clearing Dialog`
- Build / release:
  - `## Build Size & Code Optimization Guidelines`
  - `## Git Artifact Hygiene`
  - `## Release Build (per-ABI packages)`
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

- **Address bar typing must not trigger parent rebuilds.**
  - `BrowserAddressBar` already manages its own internal state and overlay. `BrowserPage` passes empty `onChanged` / `onClear` callbacks instead of `setState(() {})`.

- **Video detection script must be debounced.**
  - The injected `MutationObserver` in `_injectVideoDetectionScript()` uses a `180ms` debounce (`scheduleReport`) instead of calling `reportVideo()` on every DOM mutation.
  - Removing this debounce will cause continuous JS overhead on dynamic pages.

## Required verification when touching VLESS / proxy / WebView code

Run at least these commands:

```bash
flutter test test/browser/vless_client_test.dart test/browser/local_mixed_proxy_server_test.dart test/browser/proxy_service_test.dart
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
- If a later VLESS → client write hits `Broken pipe`, `Connection reset`, `Connection aborted`, or `Not connected` after client EOF, treat it as an expected Telegram close path rather than a protocol failure.
- **Do not** close the entire tunnel early just because the client has stopped sending.

### WebSocket Connection Pacing

- Global WebSocket connect pacing caused starvation with Telegram's parallel connections.
- The fix: **Only retry attempts are paced**, not initial connections.
- In `VlessClient._connectWithRetry()`, the retry loop has delay, but initial connection does not.
- **Do not** add global pacing that delays all concurrent WebSocket connections.

### Address Fallback

- Telegram may connect to multiple addresses in parallel (IPv4/IPv6).
- WebSocket connection now falls back to the first resolved address if the preferred fails.
- **Do not** remove the fallback logic in `_connectToWebSocket()`.

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
- incrementing `.build/version_code` exactly once after both builds finish

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

### Semantic version label + monotonic Android versionCode

- Before any user-requested compile/build step, commit the current code first so the output APK can be traced back to an exact revision.
- User-facing build labels should use `vx.x.x+<6-digit commit id>` instead of `vx.x.x+<number>`.
- The commit-based build label already carries the leading `v`; do not prepend another `v` in UI display strings.
- Android installation still requires a strictly increasing numeric `versionCode`.
- Keep the commit-based user-facing label separate from Android's monotonic numeric `versionCode`.
- Prefer supplying the commit-based label at build time from git rather than manually incrementing a numeric `+N` suffix in `pubspec.yaml` for every package.

### APK Installation Pitfall: Version Code Downgrade

Android **rejects** APK installation when the new APK's `versionCode` is lower than the currently installed version. This results in:
```
INSTALL_FAILED_VERSION_DOWNGRADE: Downgrade detected
```

**Prevention:**
- Always increment `versionCode` before building. In `pubspec.yaml`, the build number after `+` becomes the Android `versionCode`:
  ```yaml
  version: 1.0.0+2003   # 2003 is the versionCode
  ```
- If you must reinstall a lower version, uninstall first: `adb uninstall lightly.tool`
- To check current device versionCode: `adb shell dumpsys package lightly.tool | grep versionCode`

**Also update AGENTS.md** with new guidelines when they emerge from real-world fixes.

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

### EasyTier local service exposure pitfall

- If local app services should be reachable over EasyTier IP, do not exclude the whole app from VPN routing with `addDisallowedApplication(...)`.
- Also note that Dart `HttpServer.bind(..., shared: false)` may behave poorly in multi-interface mobile VPN scenarios.
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
    _pendingCompleter!.complete(<String>[]);
  }
  _pendingCompleter = null;
  _lastIssuedQuery = null;
}
```

**File**: `lib/browser/services/browser_suggestion_service.dart`

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
