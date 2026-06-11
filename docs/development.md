# Lightly 开发指南

[English](development.en.md)

## 环境要求

- Flutter 3.41.6
- Dart 3.11.4（`pubspec.yaml` 当前约束：`^3.11.4`）
- Android SDK（API 24+）
- Java 17（与 GitHub Actions 发布流程一致）
- Android NDK：建议 r27 或更高；本机已验证安装 `r27`（27.0.12077973）和 `r28c`（28.2.13676358）
- Git

### 已验证的本地工具版本

- Flutter `3.41.6`
- Dart `3.11.4`
- Rust `1.94.1`
- Cargo `1.94.1`
- `cargo-ndk` `4.1.2`
- Rust Android targets:
  - `aarch64-linux-android`
  - `armv7-linux-androideabi`

## 本地开发环境

### 推荐安装顺序

1. 安装 Flutter `3.41.6`
2. 安装 Android Studio / Android SDK / Java 17
3. 安装 Android NDK（建议 `r27+`）
4. 安装 Rust 与 Cargo
5. 安装 `cargo-ndk`
6. 安装 Rust Android targets

### 参考安装命令

```bash
# Rust / Cargo
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"

# cargo-ndk
cargo install cargo-ndk

# Rust Android targets
rustup target add aarch64-linux-android armv7-linux-androideabi
```

### Android NDK 环境变量示例

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

如需编译 EasyTier Android 原生库，建议先确认：

```bash
flutter --version
java -version
rustc --version
cargo --version
cargo ndk --version
rustup target list --installed
```

## 目录结构

```text
lightly/
├── android/                   # Android 原生代码与打包配置
├── assets/                    # 图标与静态资源
├── docs/                      # 中文/英文文档
├── lib/                       # Flutter 主体代码
├── scripts/                   # 构建脚本
└── test/                      # 单元测试与回归测试
```

## 常用命令

```bash
# 拉取依赖
flutter pub get

# 运行调试版
flutter run --debug

# 运行测试
flutter test

# 多 ABI 发布构建
bash scripts/build_multi_abi.sh
```

## 开发流程

1. 从 `main` 拉出功能或修复分支
2. 修改代码时尽量保持最小变更范围
3. 修改后运行相关测试与构建验证
4. 提交前确认没有引入新的 lint / 构建错误

## 贡献约定

建议提交信息：

```text
feat: add xxx
fix: resolve xxx
docs: update xxx
```

## CI / 发布说明

- GitHub Actions 的 Android 发布工作流位于 `.github/workflows/release.yml`
- 发布标签使用 `v*` 触发，例如 `v1.0.3`
- 当前发布工作流固定使用 Flutter `3.41.6`
- 当前仓库要求 Dart SDK 与 Flutter 版本保持兼容；Flutter `3.41.6` 对应 Dart `3.11.4`
- 发布工作流使用 Java `17`
- 发布工作流复用 `scripts/build_multi_abi.sh`，本地与 CI 应保持同一套多 ABI 构建、混淆、split-debug-info 与版本号规则

## 相关文档

- [快速入门](quickstart.md)
- [架构文档](architecture.md)
- [v1.0.7 功能更新摘要](release-summary-v1.0.7.md)
- [EasyTier 编译记录](easytier-build.md)
- [EasyTier 状态共享给 Monitor](easytier-state-sharing.md)
