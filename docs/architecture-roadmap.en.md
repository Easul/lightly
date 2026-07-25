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

## Migration Principles

1. **Contracts before moves.** Define owner, interface, state, and tests before reorganizing files.
2. **Cross-cutting infrastructure before feature layout.** Lifecycle and gateways come first.
3. **Change one dimension at a time.** Behavior, dependency inversion, moves, and renames use
   separate commits.
4. **Freeze compatibility paths.** VLESS, Telegram SOCKS5, EasyTier, remote control, and WebView
   keep-alive behavior are not rewritten opportunistically.
5. **Always remain release-ready.** Every phase passes existing tests and Release packaging.

## Phase 0: Architecture Contracts and Documentation

Status: **current phase**

Deliverables:

- Current and target architecture documents.
- Module owners, dependency direction, and design principles.
- Lifecycle, persistence, and platform-channel baselines.
- This migration roadmap.

Completion criteria:

- Documentation no longer describes the removed Dart VLESS/local mixed-proxy path.
- New code reviews can reference explicit boundary rules.

## Phase 1: Composition Root and Dependency Ports

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
4. Introduce cross-feature ports:
   - `LocalProxyEndpointProvider`
   - `SharedDownloadsAccess`
   - `RuntimeLogger`
   - `AppDatabaseProvider`

Non-goals:

- Replacing every singleton.
- Introducing a new global state-management framework.
- Moving BrowserPage or RemoteControlService.

Verification:

- `flutter test`
- Route/default-page widget tests
- Service-injection unit tests

## Phase 2: Unified Runtime Lifecycle

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

Migration order:

1. Move simple-file-manager startup out of `main.dart`.
2. Move local HTTP and clipboard auto-start out of BrowserPage initialization.
3. Move proxy runtime settings into the coordinator while WebView attachment remains behind a
   browser port.
4. Merge `AppLifecycleManager` exit behavior.
5. Reuse the same runtime policy for EasyTier and remote control.

Verification:

- Cold-start service restoration tests.
- Services continue according to settings after pages close.
- Full exit releases remote/EasyTier/native resources.
- Repeated start/stop operations remain idempotent.

## Phase 3: Platform Gateways and MainActivity Reduction

Goal: centralize and test platform contracts while leaving MainActivity with activity concerns.

Suggested extraction:

```text
Android
├── BrowserPlatformChannelHandler
├── StorageAccessChannelHandler
├── ExternalIntentChannelHandler
├── EasyTierChannelHandler
└── RemoteControlChannelHandler

Dart
├── BrowserPlatformGateway
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

## Phase 4: Persistence and Repository Boundaries

Goal: prevent storage implementation from deciding feature dependencies.

Work items:

1. Rename the code concept `BrowserDatabase` to `AppDatabase`, while retaining the physical
   `browser_data.db` filename to avoid migration risk.
2. Keep separate repositories for history, favorites, downloads, and AI chat.
3. Add `docs/data-ownership.md` recording:
   - key/table/file
   - owner
   - schema/version
   - sensitivity classification
   - backup/export policy
   - clear/delete policy
4. Add consistent key prefixes and version strategy to SharedPreferences stores.
5. Define one-way synchronization between native translation history and Dart fallback storage.

Verification:

- Upgrade from old database versions.
- Unified backup round trips.
- Clearing one data category does not delete another feature's data.

## Phase 5: Feature-first Directory Migration

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
