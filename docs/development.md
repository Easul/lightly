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

1. 确认当前分支、工作区状态和 `main` 基线。
2. 从 `main` 创建用途单一的 feature/fix/perf/refactor/docs 分支。
3. 修改代码时保持最小范围，不覆盖工作区中与当前任务无关的用户改动。
4. 按风险运行定向测试、分析和构建验证。
5. 提交前检查 staged 文件、`git diff --check` 和生成物/敏感信息。
6. 使用简洁英文 conventional commit 提交，并在交付时说明分支、commit 与验证结果。

长期有效的工作流和技术约束统一维护在根目录 `AGENTS.md` 与 `docs/`。`temp/` 只用于
可随时删除的日志、截图、实验脚本和诊断输出，不再保存规则、任务计划或设计文档。

### 分支与提交边界

- 禁止直接在 `main` 上实现修改。
- 新分支必须直接基于 `main`；如果当前处于其他 feature 分支，先核对 merge base，避免
  把无关功能带入新提交。
- 行为修改、依赖反转、文件移动、重命名应尽量拆成独立提交。
- 构建产物、`.so`、Rust `target/`、日志、密钥、代理配置和本地环境文件不得提交。
- 用户要求打包时先提交代码，再从准确 commit 进行构建。

### 验证层级

| 改动类型 | 最低验证 |
|---|---|
| 文档 | Markdown 链接、`git diff --check`、中英文一致性 |
| Dart/UI | 定向 `flutter analyze`、相关测试 |
| 共享服务/架构 | 定向测试 + 完整 `flutter test` |
| Kotlin/平台通道 | Dart contract test + Kotlin 编译/测试 |
| Rust/代理/WebView | `AGENTS.md` 对应协议测试、Flutter 测试和 Release 构建 |

不为了满足形式而在纯文档改动后构建 APK；也不能用文档校验替代运行时代码所需的测试。

## 架构变更流程

架构目标与迁移阶段见 [架构设计](architecture.md) 和
[架构迁移路线](architecture-roadmap.md)。开始结构性修改前：

1. 明确资源 owner、source of truth 和生命周期变化。
2. 先引入可测试的 contract/port，再改变依赖方向。
3. 行为修改、依赖反转、文件移动和类名重命名分别提交。
4. 目录移动应保持为纯 rename/import 变更，不顺带修复业务。
5. 新增平台能力必须通过 typed gateway，不在 Page/Widget 中创建裸 MethodChannel。
6. 新增持久化数据时记录 owner、版本、敏感级别、备份与清除策略。

复杂 feature 可以使用 presentation/application/domain/infrastructure 边界；小工具保持
浅层结构即可。不要为了统一形式全面替换现有状态管理或机械拆分 owner。

## 贡献约定

- 保持改动聚焦，避免在同一提交中混入无关重构。
- 新功能应补充测试或至少提供明确的人工验证步骤。
- 不提交本地配置、密钥、代理节点、构建产物或临时文件。
- 修改代理、EasyTier、远控或 WebView 热路径时，优先保证兼容性和性能。
- 修改页面、弹窗、设置列表或主题时，遵循 [界面设计规范](ui-design.md)，优先复用 `AppTheme`、`ColorScheme` 和现有共享组件。
- UI 调整不得顺带改变 WebView keepAlive、服务启动、socket 连接或代理协议行为。

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
- [架构迁移路线](architecture-roadmap.md)
- [工程维护待办](maintenance-backlog.md)
- [远程控制架构](remote-control-architecture.md)
- [界面设计规范](ui-design.md)
- [发布构建说明](release_build.md)
- [浏览器回归清单](browser_regression_checklist.md)
- [远程控制回归清单](remote_control_regression_checklist.md)
- [v1.0.7 功能更新摘要](release-summary-v1.0.7.md)
- [v1.0.8 功能更新摘要](release-summary-v1.0.8.md)
- [EasyTier 编译记录](easytier-build.md)
- [EasyTier 状态共享给 Monitor](easytier-state-sharing.md)
