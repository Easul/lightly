# Lightly Engineering Maintenance Backlog

[中文](maintenance-backlog.md)

## Purpose

This document consolidates still-useful items from historical temporary task plans. It is not a
schedule and does not assert that historical findings still exist. Re-audit the current code,
tests, and device baseline before implementation.

Architecture work is governed by the [Architecture Migration Roadmap](architecture-roadmap.en.md).
This file tracks independently deliverable engineering-quality candidates.

## Completed or Absorbed

- BrowserPage service wiring, tab flow, shell/widgets, and Local HTTP handlers have been extracted.
- Low-risk SettingsPage section/action decomposition is largely complete.
- RemoteControlSessionPage, connection, routing, screen pipeline, and watchdog seams exist.
- ProxyService helpers and Rust VLESS transport/handshake have been structurally split.
- `scripts/build_multi_abi.sh` owns ABI, version, obfuscation, and artifact verification policy.
- EasyTier profiles, peers, diagnostics copy, and local-service exposure have current implementations.
- The removed Dart VLESS/local mixed proxy is not a valid refactor baseline.
- The old fixed UDP audio design was replaced by WebRTC; see
  [Remote Control Architecture](remote-control-architecture.en.md).

## High Priority: Audit Before Fixing

### Async lifecycle safety

- Audit Widget updates after awaits, timers, and stream callbacks for mounted safety.
- Audit manual subscriptions, periodic timers, and listeners for symmetric cleanup.
- Audit pending Activity permission/result callbacks during destruction.
- Work from reproducible issues and clear owners instead of mechanical repository-wide rewrites.

### Error handling

- Audit Rust `unwrap()`/`expect()` on external-input and network failure paths, excluding tests and
  genuinely infallible constants.
- Audit empty catches and important `unawaited()` calls; persist only useful, sanitized diagnostics.
- Never turn frame, gesture, WebView-progress, or proxy-packet failures into high-frequency runtime
  log writes.

### Idempotent FFI/native initialization

- Ensure proxy-core panic hooks, logging, and JNI/FFI initialization register once.
- Proxy stop/start should rebuild runtime state without reinstalling global hooks.
- Platform-channel Activity Result and service references must survive destruction/recreation safely.

## Medium Priority: Execute Through the Architecture Roadmap

### App runtime coordinator

Gradually centralize startup policy for simple file manager, local HTTP, clipboard, proxy, EasyTier,
and remote control. The coordinator chooses timing; services keep resource ownership.

### MainActivity reduction

Extract browser proxy/storage/intent, EasyTier, and remote-control handlers in sequence. Establish a
typed Dart gateway and contract tests before moving Kotlin implementation.

### Data ownership

- Rename the code concept `BrowserDatabase` to `AppDatabase` without changing the database filename.
- Catalog owner, schema, sensitivity, backup, and deletion policy.
- Define one-way synchronization between native translation history and the Dart fallback.

### Large-owner convergence

- BrowserPage: extract only stable navigation/popup/runtime facades; retain WebView ownership.
- RemoteControlService: audio transport remains a high-risk seam requiring strong WebRTC coverage.
- Native video: initialization, gesture, and download workflows may move as behavior-preserving units.

## Low Priority: Data-driven Only

### Local UI updates

Move high-frequency settings groups to `ValueNotifier` only when profiling shows meaningful page
rebuild cost. Do not infer a problem from `setState()` counts or migrate state management wholesale.

### Buffering and allocation

- Rust buffer pools, `BytesMut` reuse, and copy reduction require allocation/throughput baselines.
- Never alter VLESS first-payload, SOCKS5 boundary, or half-close semantics for a zero-copy claim.
- Extract a shared Dart LRU helper only if duplication still exists and behavior is demonstrably equal.

### Named constants

The `5%` progress, `24px` scroll, and `180ms` video-detection values are compatibility/performance
contracts. Centralize them only when discoverability improves without creating a global constants
dump.

## Separate Product Proposal

The standalone native Android EasyTier camera/two-way-media idea is outside Lightly's feature-first
migration and lives in
[Native EasyTier Camera Remote Proposal](proposals/native-easytier-camera-remote.md).

## Execution Checklist

- Re-measure; do not reuse historical line counts, failure counts, or APK sizes as current facts.
- Use one focused branch directly from `main`.
- Add a test or reproduction before changing high-risk lifecycle/protocol code.
- Follow the specialized `AGENTS.md` rules for WebView, proxy, EasyTier, and remote control.
- Update or remove completed candidates here instead of creating new temporary task documents.
