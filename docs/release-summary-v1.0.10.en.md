# v1.0.10 Release Summary

This document covers the user-facing features, compatibility fixes, performance work, architecture
migration, and release-pipeline changes merged after `v1.0.8`. `v1.0.9` was an intermediate release
from the same body of work. The republished `v1.0.10` includes the complete result and an updated
private YouTube resolver binary.

## User-Facing Changes

### Optional native companions

Telegram, WebRTC voice, and EasyTier now ship as same-signed pure-Android companion APKs:

- Each feature has separate `arm64-v8a` and `armeabi-v7a` packages.
- Companions contain no FlutterEngine, Dart AOT runtime, `libflutter.so`, or second product UI.
- Lightly retains settings, configuration, backup, install prompts, and orchestration; companions own
  only native sessions, services, and JNI resources.
- Missing or incompatible companions can be installed or upgraded without blocking unrelated Lightly
  features.

Plugin delivery supports automatic, GitHub-only, and mirror-only modes. Automatic mode uses the active
Lightly proxy or direct GitHub first, then falls back to an HTTPS mirror after connection failures,
idle timeouts, or sustained low throughput. Every APK must still match the signed-in-host manifest's
URL, exact size, SHA-256, Android package, and signing certificate.

### Native YouTube resolution

Lightly integrates a private pure-Android resolver through the stable reflected
`YouTubeResolverBridge` API 1 contract:

- YouTube links open in the normal browser first; resolution starts only from the explicit in-page
  play control.
- The visible page is paused before a short-lived authenticated resolver WebView starts.
- YouTube's current MWEB player produces the muxed itag 18 request. Lightly captures the final
  validated `video/mp4` GoogleVideo URL instead of maintaining `base.js` signature logic.
- The resolved title becomes visible metadata and the initial download filename.
- Cookies, User-Agent, Referer, and complete media URLs remain in the bounded local playback/download
  context and are never persisted to logs.

The republished build pins the new resolver AAR and its SHA-256. It waits for a genuinely ready
player, polls across the full resolution budget, uses the actual WebView user agent and a measured
mobile viewport, handles renderer exits, and waits for CDN redirect candidates to settle.

### Resilient authenticated downloads

Downloads taken over from WebView now preserve a controlled request context:

- Target-origin cookies, callback User-Agent, and a sanitized Referer are forwarded.
- HTTP(S) redirects are followed explicitly with a bounded limit. Cookie, Authorization,
  Proxy-Authorization, and Referer are stripped across origins.
- Connection, TLS, response-header, idle-stream, HTTP 408/429, and 5xx failures receive bounded retry
  with backoff.
- Range resume starts from the actual partial-file length, validates `Content-Range`, and uses
  ETag/Last-Modified with `If-Range`.
- A server that ignores Range and returns 200 causes a truncate-and-restart, never duplicate append.
- Ordinary failures retain the partial file and expose retry. Only explicit record-and-file deletion
  removes the file.
- One record/path cannot be written by two active transfers.

Filename resolution now honors `Content-Disposition` including RFC 5987 `filename*`, filename-like
query parameters, final redirect paths, and known MIME extensions without overwriting a user-edited
name. A binary-looking download that resolves to an HTML login/share page fails clearly.

### Site data and browser interaction

- Download records survive restarts and keep record-only versus record-and-file deletion semantics.
- Current-site cleanup uses real Cookie domain/path metadata and clears related WebStorage,
  IndexedDB, Cache API, and Service Workers without clearing global WebView cache or unrelated sites.
- Browser overlays defer and batch non-critical page rebuilds, preserve retained WebViews, and run
  actions after route dismissal to reduce jank, white screens, and stale tab surfaces.

## Networking and Media Correctness

Proxy bypass now uses host-boundary matching: the host must equal a rule or end in `.<rule>`.
`googlevideo.com` therefore no longer matches the `google.com` bypass and unexpectedly routes DIRECT,
which had caused YouTube 403 responses.

Resolved media headers are held behind random local VideoProxyServer context tokens bound to exact
URLs. The server accepts only bounded GET/HEAD HTTP(S) GoogleVideo targets, does not follow arbitrary
upstream redirects, and never accepts client-supplied Cookie or Authorization headers.

## Companion Runtime Fixes

### Telegram

- TDLib and its private database/session moved to `lightly.tool.plugin.telegram`; the host no longer
  contains `libtdjson.so` or a Flutter TDLib package.
- Lightly remains the owner of TG Tools UI, App ID/Hash, phone number, targets, commands, and backup.
- The local SOCKS5 route is applied after TDLib parameters and refreshed when the proxy starts,
  stops, or changes port.
- The receive loop remains single-threaded across bind/rebind, and initial authorization updates are
  not consumed before the host knows the client ID.
- The companion declares its own network permission and uses a signature-protected bootstrap Activity
  to start a MIUI-compatible `dataSync` foreground service before binding.
- Host Binder death closes TDLib and foreground resources. Ordinary update logging no longer parses
  every JSON payload on the hot path.

### WebRTC voice

- `lightly.tool.plugin.webrtc` owns PeerConnectionFactory, microphone, speaker, tracks, and audio
  routing; Lightly retains control-channel signaling and EasyTier candidate policy.
- The permission Activity starts a microphone foreground service before opening the mic, supporting
  Android 14+ and MIUI background restrictions.
- ACCESS_NETWORK_STATE prevents native NetworkMonitor permission failures.
- Wired, USB, SCO, BLE headset, and hearing-aid routes follow hot-plug changes, with modern Android
  communication-device selection and a bounded MIUI SCO fallback.
- Transient permission or prepare failures remain retryable from the session controls.

### EasyTier

EasyTier JNI/FFI, instances, monitor loop, TUN fd, and VpnService moved into
`lightly.tool.plugin.easytier`. Lightly still owns profiles, backup, P2P/remote-control UI, and no-tun
policy. Network information is collected on a dedicated companion thread and cached for Binder/UI
reads, reducing duplicate JNI collection and main-thread JSON work.

## Remote Control and Architecture

- RemoteControlService remains the sole owner of control/screen sockets and session state.
- Video frames cross the typed platform gateway as the original `Uint8List`, without JSON/base64 or
  avoidable copies; performance diagnostics use bounded sampling instead of per-frame allocation.
- A `lib/app/` composition root now owns AppServices, routes, and cross-feature coordinators.
- AppRuntimeCoordinator and BrowserRuntimeCoordinator own cold-start and browser-runtime policy so
  background services no longer depend on BrowserPage remaining mounted.
- Raw Android MethodChannels were consolidated behind typed Dart gateways and focused Kotlin handlers.
- AI, Telegram, Calculator, 2048, Local Sharing, Proxy, EasyTier, Remote Control, and Video moved into
  feature boundaries at a depth proportional to their complexity.
- AppDatabase is the single physical SQLite schema owner, with documented persistence, sensitivity,
  backup, and deletion contracts.
- FloatingVideoPlayerCoordinator is the single active playback owner; unreachable duplicate player
  and resolver paths were removed.

## Release and Supply Chain

The release now coordinates three artifact groups: two Lightly APKs, six companion APKs plus the
embedded `plugins.json`, and the private obfuscated YouTube AAR.

- The AAR is fetched from a fixed HTTPS Release URL and verified with a pinned SHA-256 before Gradle.
- Private AAR access uses a fine-grained Contents: Read token that is never written to source or logs.
- Companions build with Gradle 8.14 and the same Lightly keystore, then pass ABI, no-Flutter-runtime,
  package/API, and certificate checks.
- The signed host embeds `plugins.json`; runtime installation does not trust a mutable latest manifest.
- Unchanged companions may reuse the latest verified manifest. Source/contract changes or certificate
  rotation force a rebuild.
- Detached-tag builds, portable certificate parsing, and CI Gradle provisioning were corrected.
- GitHub Releases publish APK `SHA256SUMS` and read their detailed body from
  `docs/releases/<tag>.md`.

## Upgrade Notes

- Install the APK matching the device ABI; most current devices use `arm64-v8a`.
- Telegram, WebRTC, and EasyTier may request companion installation on first use.
- The first move from host-owned TDLib to the Telegram companion requires login again. Later
  same-signed companion updates preserve that session.
- YouTube resolution requires a YouTube login inside Lightly and an explicit play action from the
  loaded watch page.

Further operational detail is available in [GitHub release delivery](github-release-delivery.md),
[optional plugin release](optional-plugin-release.md), [architecture](architecture.en.md), and
[remote-control architecture](remote-control-architecture.en.md).
