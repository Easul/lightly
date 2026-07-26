# Lightly Architecture Migration Roadmap

[中文](architecture-roadmap.md)

## Goal

This roadmap evolves the current modular monolith toward feature-first organization, one-way
dependencies, and explicit lifecycle ownership while protecting WebView, proxy, EasyTier,
remote-control, and video behavior already verified on real devices.

This is not a big-bang rewrite. Every phase must be independently mergeable, revertible, and
release-ready.

## 2026-07-25 Baseline Audit

### Code size

```text
lib/browser/           109 files
lib/pages/              77 files
lib/services/           44 files
BrowserPage           2319 lines
RemoteControlService  1305 lines
MainActivity          1122 lines
SettingsPage           789 lines
```

File size is not itself a reason to migrate, but it shows that resource owners and cross-feature
orchestration now need formal boundaries.

### Dependency state

- `pages` broadly depends on `browser`, `services`, models, and shared widgets, which matches its
  presentation role.
- Nineteen browser files depend on general services.
- Three general services depend back on browser code, creating a directory-level cycle.
- AI history directly depends on `BrowserDatabase`.
- Telegram directly depends on `ProxyService`.
- Some widgets still depend upward on pages, such as the Telegram pane.

### Lifecycle state

| Runtime | Current startup | Current shutdown | Issue |
|---|---|---|---|
| App log | `main.dart` | Settings/process exit | Mostly clear |
| Simple file manager | `main.dart`, settings page | Service/settings page | Outside unified runtime policy |
| Browser proxy | `BrowserPageInitializer`, settings | Settings/exit | Depends on BrowserPage initialization |
| Local HTTP file server | Browser initializer, settings/EasyTier page | Settings/service | Multiple orchestration entry points |
| Clipboard HTTP server | Browser, clipboard/EasyTier pages | Page/service | Multiple startup entry points |
| EasyTier | EasyTier page, remote-control flow | Pages, `AppLifecycleManager` | Policy crosses feature boundaries |
| Remote control | Remote-control pages | Pages, `AppLifecycleManager` | Owner is clear; app-exit policy is distributed |
| Overlay services | Tools/feature pages | Pages and Android services | State spans Flutter and native |

### Persistence state

- One SQLite file stores both browser and AI data.
- At least nine groups of feature SharedPreferences keys are maintained independently.
- Floating translation uses both a Dart fallback and an Android native store.
- Unified backup understands multiple sensitive feature payloads without a central ownership catalog.

### Platform bridge state

- Extracted handlers: proxy-core, floating video, translation overlay, time overlay, media scanner.
- Still inside `MainActivity`: browser proxy/file/intent, EasyTier, and remote control.
- `RemoteControlPlatformGateway` is the preferred pattern.

### Test baseline

The roadmap repeatedly requires "contract tests pass," but most of those tests do not exist yet, so
"build the test scaffolding" is itself prerequisite work and must not be hidden inside move commits.
Re-measure current coverage before starting any phase:

```bash
flutter test              # existing Dart tests
cargo test --manifest-path rust/proxy-core/Cargo.toml
find android -name '*Test.kt' | wc -l   # current Kotlin unit-test count
```

- Dart-side coverage today is mainly proxy and some browser services; there is no systematic platform
  channel contract test suite.
- The Kotlin side has almost no channel-handler unit tests, so Phase 3's "at least one test per method"
  must be scheduled as its own work item.
- Write the actual numbers into each phase's PR description; do not reuse this document's historical
  figures as current fact.

## Migration Principles

1. **Contracts before moves.** Define owner, interface, state, and tests before reorganizing files.
2. **Cross-cutting infrastructure before feature layout.** Lifecycle and gateways come first.
3. **Change one dimension at a time.** Behavior, dependency inversion, moves, and renames use
   separate commits.
4. **Freeze compatibility paths.** VLESS, Telegram SOCKS5, EasyTier, remote control, and WebView
   keep-alive behavior are not rewritten opportunistically.
5. **Always remain release-ready.** Every phase passes existing tests and Release packaging.

## Phase 0: Architecture Contracts and Documentation

Status: **complete (2026-07-26)**

Deliverables:

- Current and target architecture documents.
- Module owners, dependency direction, and design principles.
- Lifecycle, persistence, and platform-channel baselines.
- This migration roadmap.
- A **first version** of the data-ownership catalog in `docs/data-ownership.md` (key/table/file,
  owner, schema/version, sensitivity, backup, clear/delete policy). This is pure documentation with
  zero code risk and must exist before any code moves, so every later phase can check itself against
  it for "no broken implicit data contract." Phase 4 only makes the code structure catch up to this
  table; it does not create the table from scratch.

Completion criteria (exit criteria):

- Documentation no longer describes the removed Dart VLESS/local mixed-proxy path.
- New code reviews can reference explicit boundary rules.
- `docs/data-ownership.md` exists and covers every current SQLite table, SharedPreferences key group,
  and native store.
- The proxy routing/bypass correctness contract has an explicit entry in `AGENTS.md` (see
  `## Proxy Bypass / Routing Correctness`); later proxy-feature moves must reference it.

## Phase 1: Composition Root and Dependency Ports

Status: **complete (2026-07-26)**

Goal: make global dependencies explicit without changing service behavior.

Suggested additions:

```text
lib/app/
├── app.dart
├── routes.dart
├── app_scope.dart
└── app_services.dart
```

Work items:

1. Organize `MyApp`, routes, and bootstrap under `lib/app/`.
2. Compose global services explicitly in `AppServices`; existing singletons may remain initially.
3. Let pages receive services through constructors or `AppScope`, retaining defaults for gradual
   migration and tests.
4. Introduce cross-feature ports, each aimed at a dependency violation that exists today rather than
   an interface designed in the abstract:
   - `LocalProxyEndpointProvider` — removes the direct `Telegram → ProxyService` dependency; Telegram
     only takes a local SOCKS5 endpoint and stops knowing the proxy implementation.
   - `AppDatabaseProvider` — removes the direct `AI history → BrowserDatabase` dependency; AI takes a
     database handle through the provider and no longer depends on a "browser"-named class.
   - `SharedDownloadsAccess` — unifies download/backup/log-export access to the shared directory so
     features stop assembling paths independently.
   - `RuntimeLogger` — lets features log without depending back on a concrete logging service.

   Each port must land together with evidence that the old direct dependency now goes through the
   port; otherwise the port is just "designed but unused."

Non-goals:

- Replacing every singleton.
- Introducing a new global state-management framework.
- Moving BrowserPage or RemoteControlService.

Verification:

- `flutter test`
- Route/default-page widget tests
- Service-injection unit tests

Exit criteria:

- `lib/app/` exists and `main.dart` only bootstraps; it no longer assembles scattered global services.
- The four ports are defined, and at least `LocalProxyEndpointProvider` and `AppDatabaseProvider` are
  actually used by Telegram and AI — `grep` no longer shows direct `Telegram → ProxyService` or
  `AI → BrowserDatabase` construction.

Rollback:

- This phase is all new files plus dependency-injection point swaps, with no behavior change. Any
  commit can be reverted independently; if a port is unused, deleting the interface file is enough,
  with no data or protocol impact.

## Phase 2: Unified Runtime Lifecycle

Status: **code complete; pending on-device acceptance**

Implementation progress (2026-07-26):

- Persisted Simple File Manager startup has moved out of `main.dart`.
- Remote-control/EasyTier shutdown and remote-control EasyTier startup policy now live in
  `AppRuntimeCoordinator`.
- `AppLifecycleManager` now contains only Flutter lifecycle forwarding and compatibility delegates;
  it owns no concrete service.
- Cold-start restore, settings application, and shutdown for local HTTP, clipboard, and proxy now
  live in `BrowserRuntimeCoordinator`, invoked by `AppRuntimeCoordinator`.
- Settings, BrowserPage, EasyTier, Clipboard, and Simple File Manager pages now submit policy
  commands; services remain the runtime-state source of truth.
- Receiver host cleanup no longer lets `RemoteControlService` stop EasyTier directly; it calls back
  into application runtime policy.
- Remaining acceptance check: after full exit on a device, use `adb shell dumpsys` to confirm no
  capture/VPN foreground service remains.

Goal: give all background runtimes one application-level policy entry point.

Suggested API:

```text
AppRuntimeCoordinator
├── initializePersistedServices()
├── applyBrowserRuntimeSettings()
├── ensureEasyTierForRemoteControl()
├── stopFeatureRuntime(feature)
└── shutdownAll()
```

Boundaries:

- The coordinator decides when to start and stop.
- Concrete services remain owners of runtime state and native/socket resources.
- Pages submit user intent and do not duplicate `isRunning` state.

Relationship between `AppLifecycleManager` and `AppRuntimeCoordinator` (avoid overlapping
responsibilities):

- `AppRuntimeCoordinator` is the single **policy** entry point: it decides "under what conditions to
  start/stop which runtime".
- `AppLifecycleManager` is demoted to a pure **Flutter lifecycle event forwarder**: it only relays
  `paused`/`resumed`/`detached` callbacks to the coordinator and no longer decides on its own to
  shut down remote control or EasyTier.
- After migration `AppLifecycleManager` must not hold any service stop logic; if it becomes empty it
  is deleted, and exit cleanup is funnelled through `shutdownAll()`.

Migration order:

1. Move simple-file-manager startup out of `main.dart`.
2. Move local HTTP and clipboard auto-start out of BrowserPage initialization.
3. Move proxy runtime settings into the coordinator while WebView attachment remains behind a
   browser port.
4. Move existing `AppLifecycleManager` exit logic into `shutdownAll()` and convert it to event
   forwarding.
5. Reuse the same runtime policy for EasyTier and remote control.

Verification:

- Cold-start service restoration tests.
- Services continue according to settings after pages close.
- Full exit releases remote/EasyTier/native resources.
- Repeated start/stop operations remain idempotent.

Completion criteria:

- Start/stop calls for all six runtimes (simple file manager, local HTTP, clipboard, proxy runtime,
  EasyTier, remote control) go through `AppRuntimeCoordinator`; pages contain no scattered direct
  `.start()/.stop()` calls.
- `AppLifecycleManager` no longer contains any concrete service shutdown logic.
- After full app exit, `adb shell dumpsys` shows no leftover capture/VPN foreground services.

Rollback:

- The coordinator is a new orchestration layer that still calls existing service methods internally.
  If behavior breaks, first restore direct calls in pages/`main.dart` (revert the relevant move
  commit); the coordinator stays but is left unwired, leaving service implementations untouched.

## Phase 3: Platform Gateways and MainActivity Reduction

Status: **code complete (2026-07-26), pending on-device acceptance**

Goal: centralize and test platform contracts while leaving MainActivity with activity concerns.

Delivered:

- `browser_proxy` is split across browser proxy, storage access, external intent, and floating-mode
  handlers/gateways.
- `easytier_vpn` is owned by `EasyTierPlatformGateway` / `EasyTierChannelHandler`, including
  permission and monitor lifecycles.
- `remote_control` is owned by `RemoteControlPlatformGateway` / `RemoteControlChannelHandler`, with
  screen frames still passed directly as `Uint8List` / `ByteArray`.
- `MainActivity` no longer registers MethodChannel handlers directly and only delegates Activity
  Result and lifecycle events.
- Dart contract tests cover every migrated method, with Kotlin tests for critical arguments,
  permission state, and binary paths.

Suggested extraction:

```text
Android
├── BrowserPlatformChannelHandler
├── StorageAccessChannelHandler
├── ExternalIntentChannelHandler
├── EasyTierChannelHandler
└── RemoteControlChannelHandler

Dart
├── ProxyPlatformGateway
├── StorageAccessGateway
├── ExternalIntentGateway
├── EasyTierPlatformGateway
└── RemoteControlPlatformGateway
```

Requirements:

- Channel and method names exist only in gateways/handlers.
- Argument shapes use explicit models or centralized constants.
- Every method has a Dart contract test; critical channels also receive Kotlin tests.
- Binary hot paths continue using raw `Uint8List`, never JSON/Base64.

Migration order:

1. Pure `browser_proxy` proxy methods.
2. Storage and external-intent methods.
3. `easytier_vpn`.
4. `remote_control`, with screen texture and Activity Result work last.

Completion criteria:

- `MainActivity` no longer registers any `setMethodCallHandler` directly; all three target channels
  are carried by independent handlers.
- In the platform-channel table (architecture doc), the Android owner of `browser_proxy`,
  `easytier_vpn`, and `remote_control` is no longer `MainActivity`.
- Every migrated method has at least one Dart contract test, and the `remote_control` binary frame
  path still uses raw `Uint8List`.

Rollback: extract one channel per commit — first add the handler + gateway and let `MainActivity`
delegate, then delete the old `MainActivity` implementation. Rollback = revert the second step;
delegation still works and runtime behavior is unchanged.

## Phase 4: Persistence and Repository Boundaries

Status: **complete (2026-07-26)**

Delivered:

- The code owner was renamed from `BrowserDatabase` to `AppDatabase`; the physical file remains
  `browser_data.db`, schema version remains `4`, and table names/SQL are unchanged.
- History, favorites, and downloads remain owned by their repositories/stores. AI chat continues
  to obtain the shared handle through `AppDatabaseProvider` and owns its own table names.
- Contract tests now cover v3-to-v4 upgrades and category-isolated data clearing.
- `docs/data-ownership.md` matches real owners and records the SharedPreferences compatibility
  policy: freeze existing physical keys, prefix new keys by feature, and use a versioned replacement
  key plus explicit migration for incompatible format changes.
- Android translation history keeps the native store as source of truth; the Dart fallback is only
  for non-Android platforms and is never automatically merged in both directions.

Goal: prevent storage implementation from deciding feature dependencies.

Work items:

1. Rename the code concept `BrowserDatabase` to `AppDatabase`, while retaining the physical
   `browser_data.db` filename to avoid migration risk. This is a pure rename: no schema change, no
   change to table-creation SQL or serialization format, only class name and imports.
2. Keep separate repositories for history, favorites, downloads, and AI chat.
3. Fill in the real implementation details behind the `docs/data-ownership.md` catalog already
   created in Phase 0, and route AI chat through `AppDatabaseProvider` (the port introduced in
   Phase 1) instead of depending directly on `BrowserDatabase`.
4. Establish a consistent SharedPreferences prefix/version strategy while preserving existing
   physical keys across architecture refactors.
5. Define one-way synchronization between native translation history and Dart fallback storage.

Completion criteria:

- The `BrowserDatabase` class name no longer appears in code (the DB file is still `browser_data.db`).
- AI/history no longer imports the browser database implementation directly; it goes through
  `AppDatabaseProvider`.
- Every row in `docs/data-ownership.md` maps to a real owner.

Rollback: the rename commit is a pure mechanical rename — rollback = revert the single commit; the
database file and schema are never touched, so there is no data-migration risk.

Verification:

- Upgrade from old database versions.
- Unified backup round trips.
- Clearing one data category does not delete another feature's data.

## Phase 5: Feature-first Directory Migration

Status: **in progress (2026-07-26)**

Completed move-only batches:

- `lib/ai_tools/` → `lib/features/ai/`
- `lib/telegram_checkin/` → `lib/features/telegram/`
- `lib/calculator/` → `lib/features/calculator/`
- `lib/game_2048/` → `lib/features/game_2048/`
- the shared LAN-address resolver → `lib/core/network/`
- Simple File Manager, Clipboard, and Local HTTP → `lib/features/local_sharing/`
- EasyTier domain/application/infrastructure and independent widgets → `lib/features/easytier/`
- proxy domain/application/infrastructure, runtime owner, and platform gateway → `lib/features/proxy/`
- remote-control config/protocol contracts, connection/screen/voice application policies,
  socket/screen/WebRTC infrastructure, and platform gateway → `lib/features/remote_control/`
- independent remote-control screen/session/setup/dialog widgets →
  `lib/features/remote_control/presentation/widgets/`

The move batches only moved modules and updated imports; storage keys, database tables, network
protocols, and runtime owners are unchanged. Before moving local sharing, logging was inverted to
`RuntimeLogger` and Local HTTP input was narrowed to a dedicated config. Proxy logging was likewise
inverted to `RuntimeLogger`, and immutable `ProxyConfiguration` isolates `BrowserSettings`.
The EasyTier settings page remains in `lib/pages/` because it still orchestrates browser,
local-sharing, and app runtime capabilities. `RemoteControlService` remains in `lib/services/` as
the socket/session owner. The two remote-control page owners remain in `lib/pages/` while they
orchestrate app lifecycle, EasyTier, proxy, and browser settings; move them only after those
cross-feature dependencies converge, then continue with browser/video below.

Goal: resolve file-discovery problems and directory-level dependency cycles after contracts stabilize.

Recommended order:

1. `ai`, `telegram`, and `utilities`: small boundaries and lower risk.
2. `local_sharing`: after common HTTP/path primitives exist.
3. `proxy` and `easytier`: already have clear services and gateways.
4. `remote_control`: move by connection/screen/voice/protocol without changing the owner.
5. `browser` and `video`: last, because they have the most dependencies and WebView keep-alive risk.

Recommended complex-feature layout:

```text
features/<feature>/
├── presentation/       # pages/widgets
├── application/        # coordinators/use cases
├── domain/             # models/ports/policies
└── infrastructure/     # stores/platform/network implementations
```

Small features may omit empty directories.

Move rules:

- One commit moves one stable module.
- Move commits do not rename classes or change behavior.
- Import cleanup follows in a separate commit.
- `git diff` should primarily show renames.

## Phase 6: Owner Convergence and Complexity Control

Goal: reduce owner orchestration load without scattering resource ownership.

BrowserPage may further extract:

- browser runtime facade
- popup/auth/navigation facade
- media integration facade
- immutable browser view-state projection

RemoteControlService may further extract:

- session-state projection
- receiver/controller use cases
- diagnostics facade

Forbidden:

- Distributing socket fields across several long-lived services.
- Letting coordinators own BuildContext or copy mutable owner state.
- Creating callback-heavy helpers only to stay below a line-count target.

## Long-term Dependency Rules

```text
app → features → core

presentation → application → domain
infrastructure → domain

Forbidden:
core → feature
feature A → feature B infrastructure
widget → page
domain → Flutter / MethodChannel / sqflite
```

Allowed cross-feature mechanisms:

- domain port
- immutable event/model
- app-level coordinator
- shared core capability

## Per-phase Merge Checklist

- [ ] The branch is based directly on `main`.
- [ ] No unrelated feature changes are included.
- [ ] Owner/source-of-truth behavior is unchanged or explicitly migrated.
- [ ] No raw MethodChannel was added.
- [ ] No new directory-level dependency cycle was added.
- [ ] Persistence remains backward compatible.
- [ ] No page-level rebuild or persisted logging was added to a hot path.
- [ ] Focused and full Flutter tests pass.
- [ ] Native/Rust changes receive the required build and protocol tests.
- [ ] Documentation is updated.

## Explicit Non-goals

- No one-shot repository-wide directory rewrite.
- No wholesale state-management replacement.
- No forced merge of independent local-service runtimes.
- No rewrite of protocol compatibility code already verified on real nodes/devices.
- No reimplementation of Android system capabilities in Dart.
- No user-navigation or product-classification changes as a side effect of architecture work.

See the [Engineering Maintenance Backlog](maintenance-backlog.en.md) for stability audits,
performance experiments, and the disposition of historical plans. Do not maintain parallel task
documents under `temp/`.
