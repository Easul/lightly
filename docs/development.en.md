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

1. Branch from `main` for features or fixes
2. Keep changes scoped to the task
3. Run relevant tests and build verification
4. Confirm there are no new lint or build failures before committing

## Contribution Style

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
- [v1.0.7 Release Summary](release-summary-v1.0.7.en.md)
- [EasyTier Build Notes](easytier-build.en.md)
- [Sharing EasyTier State with Monitor](easytier-state-sharing.en.md)
