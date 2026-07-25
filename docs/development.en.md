# Lightly Development Guide

[中文](development.md)

## Requirements

- Flutter 3.41.6
- Dart 3.11.4 (current `pubspec.yaml` constraint: `^3.11.4`)
- Android SDK (API 24+)
- Java 17 (matching the GitHub Actions release workflow)
- Android NDK: recommend r27 or newer; this machine has verified installs of `r27` (27.0.12077973) and `r28c` (28.2.13676358)
- Git

### Verified local tool versions

- Flutter `3.41.6`
- Dart `3.11.4`
- Rust `1.94.1`
- Cargo `1.94.1`
- `cargo-ndk` `4.1.2`
- Rust Android targets:
  - `aarch64-linux-android`
  - `armv7-linux-androideabi`

## Local Setup

### Recommended installation order

1. Install Flutter `3.41.6`
2. Install Android Studio / Android SDK / Java 17
3. Install Android NDK (recommend `r27+`)
4. Install Rust and Cargo
5. Install `cargo-ndk`
6. Install the Rust Android targets

### Reference install commands

```bash
# Rust / Cargo
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"

# cargo-ndk
cargo install cargo-ndk

# Rust Android targets
rustup target add aarch64-linux-android armv7-linux-androideabi
```

### Example Android NDK environment variables

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export ANDROID_NDK_ROOT="$HOME/Android/Sdk/ndk/28.2.13676358"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
```

```bash
git clone https://github.com/Easul/lightly.git
cd lightly
flutter pub get
flutter doctor
```

If you also need to build the EasyTier Android native libraries, verify the toolchain first:

```bash
flutter --version
java -version
rustc --version
cargo --version
cargo ndk --version
rustup target list --installed
```

## Repository Layout

```text
lightly/
├── android/                   # Android native code and packaging config
├── assets/                    # Icons and static resources
├── docs/                      # Chinese and English docs
├── lib/                       # Main Flutter code
├── scripts/                   # Build scripts
└── test/                      # Unit and regression tests
```

## Common Commands

```bash
# Install dependencies
flutter pub get

# Run debug build
flutter run --debug

# Run tests
flutter test

# Multi-ABI release build
bash scripts/build_multi_abi.sh
```

## Development Flow

1. Confirm the current branch, worktree state, and `main` baseline.
2. Create a focused feature/fix/perf/refactor/docs branch directly from `main`.
3. Keep changes scoped and preserve unrelated user changes in the worktree.
4. Run targeted tests, analysis, and build verification in proportion to risk.
5. Before committing, review staged files, run `git diff --check`, and exclude generated or
   sensitive artifacts.
6. Commit with a concise English conventional message and report the branch, commit, and
   verification during handoff.

Durable workflow and technical guidance belongs in root `AGENTS.md` or `docs/`. `temp/` is only
for disposable logs, screenshots, experiment scripts, and diagnostic output; it must not contain
rules, task plans, or design documents.

### Branch and commit boundaries

- Never implement directly on `main`.
- New work must branch directly from `main`. If another feature branch is checked out, verify the
  merge base so unrelated work is not inherited.
- Separate behavior changes, dependency inversion, file moves, and renames when practical.
- Do not commit build outputs, `.so` files, Rust `target/`, logs, keys, proxy configuration, or
  local environment files.
- When the user requests packaging, commit first and build from the exact revision.

### Verification levels

| Change | Minimum verification |
|---|---|
| Documentation | Markdown links, `git diff --check`, Chinese/English consistency |
| Dart/UI | Targeted `flutter analyze` and related tests |
| Shared service/architecture | Targeted tests plus full `flutter test` |
| Kotlin/platform channel | Dart contract tests plus Kotlin compilation/tests |
| Rust/proxy/WebView | Relevant `AGENTS.md` protocol tests, Flutter tests, and Release build |

Do not build an APK merely for documentation-only changes, and do not substitute documentation
checks for runtime verification when code changes.

## Architecture Change Workflow

See [Architecture Design](architecture.en.md) and the
[Architecture Migration Roadmap](architecture-roadmap.en.md). Before structural work:

1. Identify the resource owner, source of truth, and lifecycle change.
2. Introduce a testable contract/port before reversing dependencies.
3. Separate behavior changes, dependency inversion, file moves, and class renames into different
   commits.
4. Directory moves should remain pure rename/import changes without opportunistic fixes.
5. New platform capabilities must use typed gateways; do not create raw MethodChannels in pages or
   widgets.
6. New persisted data must document owner, version, sensitivity, backup policy, and deletion policy.

Complex features may use presentation/application/domain/infrastructure boundaries. Small tools
should remain shallow. Do not replace the state model wholesale or split owners mechanically for
uniformity.

## Contribution Style

- Keep changes focused and avoid unrelated refactors in the same commit.
- Add tests for new behavior or provide explicit manual verification steps.
- Do not commit local configuration, secrets, proxy nodes, build outputs, or temporary files.
- When changing proxy, EasyTier, remote-control, or WebView hot paths, preserve compatibility and performance first.
- For pages, dialogs, settings lists, or theme changes, follow [UI Design Guidelines](ui-design.en.md) and prefer the existing `AppTheme`, `ColorScheme`, and shared components.
- UI work must not implicitly change WebView keep-alive behavior, service startup, socket connections, or proxy protocol behavior.

Recommended commit formats:

```text
feat: add xxx
fix: resolve xxx
docs: update xxx
```

## CI / Release Notes

- The Android release workflow lives in `.github/workflows/release.yml`
- Release tags are triggered by `v*`, such as `v1.0.3`
- The current release workflow pins Flutter `3.41.6`
- Dart SDK constraints must stay compatible with the Flutter version; Flutter `3.41.6` ships with Dart `3.11.4`
- The release workflow uses Java `17`
- The release workflow reuses `scripts/build_multi_abi.sh`, so local and CI releases share the same multi-ABI build, obfuscation, split-debug-info, and versioning rules

## Related Docs

- [Quick Start](quickstart.en.md)
- [Architecture](architecture.en.md)
- [Architecture Migration Roadmap](architecture-roadmap.en.md)
- [Engineering Maintenance Backlog](maintenance-backlog.en.md)
- [Remote Control Architecture](remote-control-architecture.en.md)
- [UI Design Guidelines](ui-design.en.md)
- [Release Build Guide](release_build.md)
- [Browser Regression Checklist](browser_regression_checklist.md)
- [Remote Control Regression Checklist](remote_control_regression_checklist.md)
- [v1.0.7 Release Summary](release-summary-v1.0.7.en.md)
- [v1.0.8 Release Summary](release-summary-v1.0.8.en.md)
- [EasyTier Build Notes](easytier-build.en.md)
- [Sharing EasyTier State with Monitor](easytier-state-sharing.en.md)
