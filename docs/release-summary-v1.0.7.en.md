# v1.0.7 Release Summary

This document summarizes the main changes brought by the current feature branch before merging into `main`, so release notes, regression checks, and future maintenance can refer to one source.

## New Capabilities

- **Simple File Manager**: adds **Settings → 文件简易管理**, default root `/storage/emulated/0`, default port `12580`, a web file tree, common text-file editing and saving, delete confirmation, favorite paths, and responsive mobile/desktop UI.
- **Remote Control Enhancements**: controller sessions support minimizing to a floating dot, temporary close, wake-screen, single-direction vs trajectory swipe modes, keyboard input, and remote annotation circles.
- **P2P / EasyTier no-VPN Mode**: P2P settings support no-tun/no-VPN startup; remote control can reuse an existing no-VPN EasyTier instance and connect to `10.126.*` targets through the no-tun SOCKS5 portal.
- **EasyTier State Sharing**: exposes EasyTier runtime state through a signature-permission protected ContentProvider, allowing a same-signature Monitor app to reuse Lightly's P2P VPN state.
- **Parser Video Titles**: native video parser responses can include `title`, now used for the player header and initial download filename.
- **Proxy Node Management**: proxy settings can save, select, and delete multiple nodes while showing protocol-specific fields.

## Reliability and Compatibility

- Redmi / Qualcomm remote-screen black-screen paths now include capture-size fallback and delayed decoder reconfiguration for high-resolution AVC failures.
- Remote screen sending drops stale delta frames and keeps the latest frame to reduce perceived latency under weak networks.
- Remote connection handling distinguishes port probes from real controller sessions to avoid false disconnect prompts.
- EasyTier no-tun SOCKS ordering, port mappings, and shutdown lifecycle were tightened to avoid port conflicts, instance restarts, and lingering VPN indicators.
- Browser overlay, tab switching, WebView keep-alive, download playback, find-in-page, and external file-open paths received stability fixes.
- Local SOCKS5 / Telegram compatibility fixes cover auth negotiation, CONNECT bind replies, and half-close error classification.

## Structural Refactoring

- Browser / Remote / EasyTier / Downloads / Proxy pages and widgets were split into action, section, helper, and coordinator files to reduce large-file complexity.
- Browser backup was split into model, file-writer, and Web-data collection components.
- Floating video controls, favorites dialogs, remote setup/session widgets, and EasyTier settings actions were extracted into dedicated components.

## Release and Verification

- `scripts/build_multi_abi.sh` is the single entry point for multi-ABI release builds and produces both `app-arm64-v8a-release.apk` and `app-armeabi-v7a-release.apk`.
- GitHub Actions release workflow now calls the same script so local and CI builds share `TARGET_ABI`, obfuscation, split-debug-info, and versioning rules.
- Android `versionCode` remains `5000 + main branch commit count`; user-facing versions use `vX.Y.Z+<6-char commit>`.

## Suggested Regression Focus

1. **Settings → 文件简易管理**: start service, browse directories, edit/save text files, confirm deletion, scroll favorites, and test LAN access.
2. Remote control over LAN and EasyTier `10.126.*`: screen, touch, keyboard, trajectory swipe, annotation, temporary close, minimize, and full cleanup.
3. Redmi / Qualcomm devices: first receiver frame appears and controller decoding does not stay black at high resolution.
4. P2P no-VPN: no system VPN permission/icon, and an existing P2P no-tun instance can be reused by remote control.
5. Browser: tab/overlay animation, download playback, external file open, X/YouTube mobile layout, site-data clearing, and backup restore.
