# EasyTier Build Notes

[中文](easytier-build.md)

This document records how the EasyTier Android native libraries used by this Flutter repo were built from the EasyTier source repo and verified against the vendored `jniLibs` artifacts.

## Recommended Script Entrypoint

This repo now includes a reusable script:

```bash
bash scripts/build_easytier_android.sh
```

The script will:

1. default to reusing or cloning EasyTier under this repo at `build/EasyTier`
2. clone `https://github.com/Easul/EasyTier` there if `build/EasyTier` does not exist yet
3. create or reuse a local build branch from the verified base commit
4. apply the JNI fixes automatically and rebuild the Android `.so` libraries
5. automatically copy the rebuilt libraries into this Flutter repo under `android/app/src/main/jniLibs/`
6. compare the rebuilt outputs with the vendored Flutter `jniLibs`

The script also supports automatic parallel builds:

- if a multi-core CPU is detected, it uses parallel compilation through `CARGO_BUILD_JOBS`
- you can also override it manually: `EASYTIER_BUILD_JOBS=8 bash scripts/build_easytier_android.sh`

If the older `build/easytier-fork/EasyTier` directory exists, the script automatically migrates it to the new default location `build/EasyTier`.

## Source Baseline Used by the Script

- Default source repo path: `build/EasyTier`
- Branch created/reused by the script: `lightly/android-jni-b20075e3`
- Commit used for this verification: `b20075e3dca788e968d758b247242e92970eadb2`

### Source-repo working tree state during verification

The EasyTier source repo was not clean when this build was verified. These local changes were present:

- `M easytier-contrib/easytier-android-jni/Cargo.toml`
- `M easytier-contrib/easytier-android-jni/build.sh`
- `M easytier-contrib/easytier-android-jni/src/lib.rs`
- `?? easytier-contrib/easytier-android-jni/build.rs`
- `?? tauri-plugin-vpnservice/android/.gradle/`

If you need a fully reproducible release procedure, clean the EasyTier working tree first and record a fresh commit before rebuilding.

The local build branch name currently used by the script is:

```text
lightly/android-jni-b20075e3
```

## Target Libraries

This Flutter repo consumes these native libraries:

- `android/app/src/main/jniLibs/arm64-v8a/libeasytier_android_jni.so`
- `android/app/src/main/jniLibs/arm64-v8a/libeasytier_ffi.so`
- `android/app/src/main/jniLibs/armeabi-v7a/libeasytier_android_jni.so`
- `android/app/src/main/jniLibs/armeabi-v7a/libeasytier_ffi.so`

The script automatically overwrites these four files after a successful build.

## Requirements

- Rust `1.94.1`
- Cargo `1.94.1`
- `cargo-ndk` `4.1.2`
- Android NDK: recommend `r27+`; this machine has verified installs of `r27` (27.0.12077973) and `r28c` (28.2.13676358)
- Rust Android targets:
  - `aarch64-linux-android`
  - `armv7-linux-androideabi`
- Also recommended for full app builds: Flutter `3.41.6` / Dart `3.11.4` / Java `17`

### Example environment setup

```bash
# Rust / Cargo
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"

# cargo-ndk
cargo install cargo-ndk

# Rust Android targets
rustup target add aarch64-linux-android armv7-linux-androideabi

# Example Android SDK / NDK environment variables
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export ANDROID_NDK_ROOT="$HOME/Android/Sdk/ndk/28.2.13676358"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
```

Verified locally with:

```bash
flutter --version
java -version
rustc --version
cargo --version
cargo ndk --version
rustup target list --installed
```

## Build Entrypoint

The direct build entrypoint in the EasyTier repo is:

```bash
build/EasyTier/easytier-contrib/easytier-android-jni/build.sh
```

That script:

1. checks `cargo-ndk`
2. ensures the Rust Android targets are installed
3. builds `easytier-ffi` first
4. builds `easytier-android-jni` second
5. attempts to copy outputs into `easytier-contrib/easytier-android-jni/target/android/`

The Flutter-repo script `scripts/build_easytier_android.sh` now ensures `build/EasyTier` is ready first, then invokes that upstream JNI build script.

## Commands Used for This Verification

### One-shot script

```bash
cd build/EasyTier
bash easytier-contrib/easytier-android-jni/build.sh
```

### Equivalent step-by-step commands

```bash
cd build/EasyTier/easytier-contrib/easytier-ffi
cargo ndk -t arm64-v8a build --release
cargo ndk -t armeabi-v7a build --release

cd build/EasyTier/easytier-contrib/easytier-android-jni
cargo ndk -t arm64-v8a build --release
cargo ndk -t armeabi-v7a build --release
```

## Actual Output Paths Used in This Verification

In this environment, the directly comparable outputs were available under Cargo's top-level target directories:

- `build/EasyTier/target/aarch64-linux-android/release/libeasytier_android_jni.so`
- `build/EasyTier/target/aarch64-linux-android/release/libeasytier_ffi.so`
- `build/EasyTier/target/armv7-linux-androideabi/release/libeasytier_android_jni.so`
- `build/EasyTier/target/armv7-linux-androideabi/release/libeasytier_ffi.so`

Although `build.sh` contains copy logic for `easytier-contrib/easytier-android-jni/target/android/`, that directory was not generated in this run, so the comparison was performed directly against `target/*/release/*.so`.

## Comparison with Vendored Flutter `jniLibs`

### Result

All 4 libraries were **byte-for-byte identical**.

### SHA-256

| ABI | Library | SHA-256 |
|---|---|---|
| arm64-v8a | `libeasytier_android_jni.so` | `11743857fca8ea42d04f86bbb6a7a545ee6dbdd821a8b5671526955b02334717` |
| arm64-v8a | `libeasytier_ffi.so` | `c3dd1b2ffeaa7096a992c417f297abdf752ac0e3f2267dd4ee9317a69f9a2557` |
| armeabi-v7a | `libeasytier_android_jni.so` | `6ddfdf2c5efa0ad7695335091ebc179ab007d0744d07fafcc6e9504d172aae05` |
| armeabi-v7a | `libeasytier_ffi.so` | `869241b06fc46d613fcdc9e15351a7c51bc36d0c1b33e3d831e8f69678549a3f` |

These hashes matched both:

- the EasyTier source-repo build outputs from this verification
- the checked-in `.so` files under `android/app/src/main/jniLibs/` in this Flutter repo

## Updating the Flutter Repo Libraries

If you run:

```bash
bash scripts/build_easytier_android.sh
```

the script now copies all four `.so` files into `android/app/src/main/jniLibs/` automatically after a successful build, so a separate manual copy step is usually unnecessary.

If you still want to copy them manually, use the commands below:

After rebuilding EasyTier, copy the new libraries into this repo:

```bash
cp build/EasyTier/target/aarch64-linux-android/release/libeasytier_android_jni.so android/app/src/main/jniLibs/arm64-v8a/
cp build/EasyTier/target/aarch64-linux-android/release/libeasytier_ffi.so android/app/src/main/jniLibs/arm64-v8a/
cp build/EasyTier/target/armv7-linux-androideabi/release/libeasytier_android_jni.so android/app/src/main/jniLibs/armeabi-v7a/
cp build/EasyTier/target/armv7-linux-androideabi/release/libeasytier_ffi.so android/app/src/main/jniLibs/armeabi-v7a/
```

## Recommended Verification After Updating

1. Confirm all four `.so` files were replaced under `jniLibs/`
2. Re-test the EasyTier feature path
3. At minimum, confirm:
   - JNI loading still works
   - `collectNetworkInfos()` is callable
   - the VPN startup path does not crash
   - arm64 and armv7 packaging still succeeds
