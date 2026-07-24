# v1.0.8 Release Summary

This document summarizes the main capabilities, fixes, and refactors merged into `main` between `v1.0.7` and `v1.0.8`, so release notes, regression checks, and future maintenance can refer to one source.

## New Capabilities

- **AI Translation & Chat Tools**: new AI translation tool and AI chat page, with streaming responses, persisted history, AI configuration management, and lightweight Markdown rendering.
- **Telegram Check-in Tool**: TDLib integration with a Telegram check-in page and chat pane, message text selection, and traffic routed through the local proxy.
- **Browser History Management**: a dedicated history page for viewing, searching, and clearing browsing history; the search bar collapses automatically while scrolling.
- **Desktop Mode & Viewport Control**: switch between desktop and mobile viewports; desktop mode recreates the WebView so it applies immediately, with a paginated action panel on narrow screens.
- **Web Debug Console**: an in-page web debug console together with several browser performance fixes.
- **Video Cache & Speed Test Controls**: native playback gains media cache and speed test controls; the time overlay can show milliseconds.
- **Download Management Enhancements**: download records are separated from files, so a file or only its record can be deleted independently.
- **More Tools Panel Polish**: the browser "More" sheet is reorganized into a tighter, clearer set of actions.

## Reliability and Compatibility Fixes

- **SOCKS5 / Proxy**: CONNECT replies are sent atomically and separated from payload, Hysteria2 IPv6 targets are formatted correctly, Telegram downstream is preserved with a delayed first packet, and Telegram stability over Hysteria2 is improved.
- **Popups & External Links**: raw popup URLs are captured before normalization, encoded external app URLs are preserved, and popup dialogs stay decoded consistently, fixing dropped parameters on cross-app jumps.
- **Browser**: force-refresh of stalled pages, desktop-mode WebView recreation, immediate viewport application, favorites search alignment, and local tab preservation.
- **Runtime Logging**: broader runtime log coverage and logs reset between sessions, making issues easier to diagnose.
- **Lifecycle**: Telegram and overlay lifecycle tightened; multi-ABI builds and file manager layout hardened.

## Structural Refactoring

- **WebView Decomposition**: navigation controller, event controller, script service, state reader, diagnostics, and popup URL resolver extracted from `browser_page`, significantly reducing single-file complexity.
- **Independent Android Channels**: floating video, media scanner, proxy core, time overlay, and translation overlay split into dedicated `ChannelHandler` + `Service` pairs.
- **Settings & Forms**: proxy node controller, proxy form mutator, and settings form controller made independent, clarifying the proxy settings page logic.
- **Remote Control Platform Access**: platform-specific access centralized into `RemoteControlPlatformGateway`, further converging the remote control service and page helpers.
- **Visual Simplification**: overall app visual design and service boundaries reorganized for a lighter, more consistent interface.

## Performance

- AI chat streaming rendering and history queue efficiency optimized; long conversations scroll and render more smoothly.

## Documentation

- Expanded UI design guidelines and project guidance (`docs/ui-design.md` / `ui-design.en.md`, plus development and architecture docs).

## Release and Verification

- Continues to use `scripts/build_multi_abi.sh` for multi-ABI release builds, producing `app-arm64-v8a-release.apk` and `app-armeabi-v7a-release.apk`.
- Android `versionCode` remains `5000 + main branch commit count`; user-facing versions use `vX.Y.Z+<6-char commit>`.

## Suggested Regression Focus

1. **AI Tools**: translation, AI chat streaming output, history persistence and loading, and AI settings.
2. **Telegram**: check-in flow, chat message text selection, send/receive via the local proxy, and stability over Hysteria2.
3. **Browser**: history page search/clear, desktop/mobile mode switching, web debug console, popup and external-link jumps, and force refresh.
4. **Video**: media cache and speed test, millisecond time overlay, and full parser endpoint compatibility.
5. **Proxy**: SOCKS5 high-throughput relay, IPv6 targets, and the diagnostic logging toggle.
6. **Downloads**: independent record/file deletion and in-page playback.
