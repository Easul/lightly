# EasyTier 编译记录

[English](easytier-build.en.md)

本文档记录了当前仓库使用的 EasyTier Android 原生库是如何从源码仓库编译并比对验证的。

## 推荐脚本入口

当前仓库已内置一份可复用脚本：

```bash
bash scripts/build_easytier_android.sh
```

这个脚本会：

1. 默认在当前仓库的 `build/EasyTier` 下复用或拉取 EasyTier
2. 如果 `build/EasyTier` 不存在，则从 `https://github.com/Easul/EasyTier` 克隆到这里
3. 基于本次验证使用的 commit 创建/复用本地构建分支
4. 自动填充 JNI 修复内容后重新编译 Android `.so`
5. 编译成功后自动复制到当前 Flutter 仓库的 `android/app/src/main/jniLibs/`
6. 自动和当前 Flutter 仓库中的 `jniLibs` 做一致性比对

脚本同时支持自动并行编译：

- 若检测到多核 CPU，会自动通过 `CARGO_BUILD_JOBS` 使用多核并行编译
- 也可以手动指定：`EASYTIER_BUILD_JOBS=8 bash scripts/build_easytier_android.sh`

如果脚本发现旧的 `build/easytier-fork/EasyTier` 目录存在，它会自动迁移到新的默认位置 `build/EasyTier`。

## 本次脚本使用的源码基线

- 默认源码仓库路径：`build/EasyTier`
- 本次脚本创建/复用的分支：`lightly/android-jni-b20075e3`
- 本次验证时提交：`b20075e3dca788e968d758b247242e92970eadb2`

### 本次验证时源码仓库工作区状态

编译时 EasyTier 源码仓库不是干净工作区，存在以下未提交修改：

- `M easytier-contrib/easytier-android-jni/Cargo.toml`
- `M easytier-contrib/easytier-android-jni/build.sh`
- `M easytier-contrib/easytier-android-jni/src/lib.rs`
- `?? easytier-contrib/easytier-android-jni/build.rs`
- `?? tauri-plugin-vpnservice/android/.gradle/`

如果后续需要可复现的发布流程，建议先在 EasyTier 源码仓库中清理工作区，再重新编译并记录新的提交号。

当前脚本默认创建/复用的本地构建分支名为：

```text
lightly/android-jni-b20075e3
```

## 目标产物

当前 Flutter 仓库实际使用以下原生库：

- `android/app/src/main/jniLibs/arm64-v8a/libeasytier_android_jni.so`
- `android/app/src/main/jniLibs/arm64-v8a/libeasytier_ffi.so`
- `android/app/src/main/jniLibs/armeabi-v7a/libeasytier_android_jni.so`
- `android/app/src/main/jniLibs/armeabi-v7a/libeasytier_ffi.so`

脚本在构建完成后会自动覆盖更新这 4 个文件。

## 依赖要求

- Rust `1.94.1`
- Cargo `1.94.1`
- `cargo-ndk` `4.1.2`
- Android NDK：建议 `r27+`；本机已验证安装 `r27`（27.0.12077973）与 `r28c`（28.2.13676358）
- Rust Android targets:
  - `aarch64-linux-android`
  - `armv7-linux-androideabi`
- 额外建议：Flutter `3.41.6` / Dart `3.11.4` / Java `17`

### 环境安装示例

```bash
# Rust / Cargo
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"

# cargo-ndk
cargo install cargo-ndk

# Rust Android targets
rustup target add aarch64-linux-android armv7-linux-androideabi

# Android SDK / NDK 示例环境变量
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export ANDROID_NDK_ROOT="$HOME/Android/Sdk/ndk/28.2.13676358"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
```

已验证本机存在：

```bash
flutter --version
java -version
rustc --version
cargo --version
cargo ndk --version
rustup target list --installed
```

## 实际使用的构建入口

EasyTier 源码仓库中可直接使用：

```bash
build/EasyTier/easytier-contrib/easytier-android-jni/build.sh
```

这个脚本会：

1. 检查 `cargo-ndk`
2. 检查并安装 Android Rust target
3. 先编译 `easytier-ffi`
4. 再编译 `easytier-android-jni`
5. 尝试复制产物到 `easytier-contrib/easytier-android-jni/target/android/`

而当前 Flutter 仓库中的 `scripts/build_easytier_android.sh` 会先确保 `build/EasyTier` 就绪，再调用这份上游 JNI 构建脚本。

## 本次验证使用的命令

### 一键脚本

```bash
cd build/EasyTier
bash easytier-contrib/easytier-android-jni/build.sh
```

### 等价的分步命令

```bash
cd build/EasyTier/easytier-contrib/easytier-ffi
cargo ndk -t arm64-v8a build --release
cargo ndk -t armeabi-v7a build --release

cd build/EasyTier/easytier-contrib/easytier-android-jni
cargo ndk -t arm64-v8a build --release
cargo ndk -t armeabi-v7a build --release
```

## 本次验证得到的实际产物路径

这次本机执行后，**可直接用于比对的产物在 Cargo 根 target 目录下**：

- `build/EasyTier/target/aarch64-linux-android/release/libeasytier_android_jni.so`
- `build/EasyTier/target/aarch64-linux-android/release/libeasytier_ffi.so`
- `build/EasyTier/target/armv7-linux-androideabi/release/libeasytier_android_jni.so`
- `build/EasyTier/target/armv7-linux-androideabi/release/libeasytier_ffi.so`

虽然 `build.sh` 代码里包含复制到 `easytier-contrib/easytier-android-jni/target/android/` 的逻辑，但这次执行后该目录没有生成，所以本次比对直接使用上面的 `target/*/release/*.so`。

## 与当前 Flutter 仓库内置 so 的一致性比对

### 结果

4 个库全部 **byte-for-byte 一致**。

### SHA-256

| ABI | Library | SHA-256 |
|---|---|---|
| arm64-v8a | `libeasytier_android_jni.so` | `11743857fca8ea42d04f86bbb6a7a545ee6dbdd821a8b5671526955b02334717` |
| arm64-v8a | `libeasytier_ffi.so` | `c3dd1b2ffeaa7096a992c417f297abdf752ac0e3f2267dd4ee9317a69f9a2557` |
| armeabi-v7a | `libeasytier_android_jni.so` | `6ddfdf2c5efa0ad7695335091ebc179ab007d0744d07fafcc6e9504d172aae05` |
| armeabi-v7a | `libeasytier_ffi.so` | `869241b06fc46d613fcdc9e15351a7c51bc36d0c1b33e3d831e8f69678549a3f` |

这些哈希同时匹配：

- EasyTier 源码仓库本次构建输出
- 当前 Flutter 仓库 `android/app/src/main/jniLibs/` 中已提交的 `.so`

## 更新 Flutter 仓库中的 EasyTier 库

如果直接使用：

```bash
bash scripts/build_easytier_android.sh
```

那么脚本会在构建成功后自动把 4 个 `.so` 复制到 `android/app/src/main/jniLibs/`，通常不需要再手动复制。

如果你只想手动复制，也可以使用下面这些命令：

当 EasyTier 源码发生变化并重新编译后，将新库复制到本仓库：

```bash
cp build/EasyTier/target/aarch64-linux-android/release/libeasytier_android_jni.so android/app/src/main/jniLibs/arm64-v8a/
cp build/EasyTier/target/aarch64-linux-android/release/libeasytier_ffi.so android/app/src/main/jniLibs/arm64-v8a/
cp build/EasyTier/target/armv7-linux-androideabi/release/libeasytier_android_jni.so android/app/src/main/jniLibs/armeabi-v7a/
cp build/EasyTier/target/armv7-linux-androideabi/release/libeasytier_ffi.so android/app/src/main/jniLibs/armeabi-v7a/
```

## 更新后建议验证

1. 确认四个 `.so` 都已覆盖到 `jniLibs/`
2. 运行相关 EasyTier 功能验证
3. 至少确认：
   - JNI 加载正常
   - `collectNetworkInfos()` 可调用
   - VPN 启动流程不崩溃
   - arm64 / armv7a 打包仍然正常
