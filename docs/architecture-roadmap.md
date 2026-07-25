# Lightly 架构迁移路线

[English](architecture-roadmap.en.md)

## 目标

本路线用于把现有模块化单体逐步迁移到 feature-first、依赖单向、生命周期明确的结构，
同时保护已经通过真实设备验证的 WebView、代理、EasyTier、远控和视频兼容性。

这不是一次“大重写”。每个阶段都必须可以独立合并、独立回退并保持可发布。

## 2026-07-25 基线审计

### 代码规模

```text
lib/browser/           109 files
lib/pages/              77 files
lib/services/           44 files
BrowserPage           2319 lines
RemoteControlService  1305 lines
MainActivity          1122 lines
SettingsPage           789 lines
```

文件大小本身不是迁移理由，但它说明资源 owner 和跨功能编排已经进入需要正式边界的阶段。

### 依赖现状

- `pages` 广泛依赖 `browser`、`services`、`models` 和共享 widgets，符合展示层角色。
- `browser` 有 19 个文件依赖通用 `services`。
- `services` 有 3 个文件反向依赖 `browser`，形成目录级双向依赖。
- AI 历史直接依赖 `BrowserDatabase`。
- Telegram 直接依赖 `ProxyService`。
- Widget 仍有反向依赖 Page 的情况，例如 Telegram pane。

### 生命周期现状

| Runtime | 当前启动位置 | 当前关闭位置 | 问题 |
|---|---|---|---|
| App log | `main.dart` | 设置/进程结束 | 基本清晰 |
| Simple file manager | `main.dart`、设置页 | 服务自身/设置页 | 独立于统一 runtime |
| Browser proxy | `BrowserPageInitializer`、设置页 | 设置页/退出 | 依赖 BrowserPage 初始化 |
| Local HTTP file server | `BrowserPageInitializer`、设置/EasyTier 页 | 设置页/服务自身 | 多个协调入口 |
| Clipboard HTTP server | BrowserPage、Clipboard/EasyTier 页 | 页面/服务自身 | 多个启动入口 |
| EasyTier | EasyTier 页、远控流程 | 页面、`AppLifecycleManager` | 运行策略跨 feature |
| Remote control | 远控页面 | 页面、`AppLifecycleManager` | Owner 清晰，应用退出策略分散 |
| Overlay services | Tools/feature pages | 页面和 Android service | 状态跨 Flutter/native |

### 存储现状

- 一个 SQLite 文件同时保存浏览器和 AI 数据。
- 至少九组 feature SharedPreferences key 独立维护。
- 悬浮翻译同时涉及 Dart fallback 与 Android native store。
- 备份功能需要理解多个 feature 的敏感数据，但缺少统一数据目录清单。

### 平台桥接现状

- 已独立 Handler：proxy-core、floating video、translation overlay、time overlay、media scanner。
- 仍集中在 `MainActivity`：browser proxy/file/intent、EasyTier、remote control。
- `RemoteControlPlatformGateway` 已提供良好模板。

## 迁移原则

1. **先契约，后移动。** 先定义 owner、接口、状态和测试，再迁目录。
2. **先横向基础设施，后 feature 重排。** 生命周期和 platform gateway 优先于文件分类。
3. **一次只改变一个维度。** 行为、依赖反转、文件移动、命名迁移分别提交。
4. **兼容性路径冻结。** VLESS、Telegram SOCKS5、EasyTier、远控和 WebView keepAlive
   在对应迁移阶段不得顺带重写。
5. **应用始终可发布。** 每阶段完成后必须能通过现有测试与 Release 构建。

## Phase 0：架构契约与文档

状态：**当前阶段**

交付物：

- 当前/目标架构文档。
- 模块 owner、依赖方向和设计原则。
- 生命周期、持久化和平台通道基线。
- 本迁移路线。

完成标准：

- 文档不再描述已经删除的 Dart VLESS/local mixed proxy 路径。
- 新代码评审可以引用明确的边界规则。

## Phase 1：Composition Root 与依赖接口

目标：减少隐藏单例依赖，但不改变服务行为。

建议新增：

```text
lib/app/
├── app.dart
├── routes.dart
├── app_scope.dart
└── app_services.dart
```

工作项：

1. 把 `MyApp`、路由表和 bootstrap 组织到 `lib/app/`。
2. 用 `AppServices` 明确组装全局 service；初期可以继续引用现有 singleton。
3. 页面优先通过构造参数或 `AppScope` 获取 service，保留默认值支持渐进迁移和测试。
4. 抽出跨 feature ports：
   - `LocalProxyEndpointProvider`
   - `SharedDownloadsAccess`
   - `RuntimeLogger`
   - `AppDatabaseProvider`

非目标：

- 不替换所有 singleton。
- 不引入新的全局状态管理框架。
- 不移动 BrowserPage 或 RemoteControlService。

验证：

- `flutter test`
- 路由与默认页 Widget 测试
- service 注入单元测试

## Phase 2：统一 Runtime 生命周期

目标：所有后台 runtime 有唯一应用级策略入口。

建议新增：

```text
AppRuntimeCoordinator
├── initializePersistedServices()
├── applyBrowserRuntimeSettings()
├── ensureEasyTierForRemoteControl()
├── stopFeatureRuntime(feature)
└── shutdownAll()
```

边界：

- Coordinator 决定何时启动/停止。
- 具体 service 仍是运行状态和 native/socket 资源 owner。
- 页面只提交用户意图，不复制 `isRunning` source of truth。

迁移顺序：

1. Simple file manager startup 从 `main.dart` 移入 coordinator。
2. Local HTTP 与 clipboard auto-start 从 BrowserPage 初始化移入 coordinator。
3. Proxy settings runtime 应用移入 coordinator，但 WebView proxy attach 仍通过 browser port。
4. 合并 `AppLifecycleManager` 的退出逻辑。
5. EasyTier/remote-control 复用同一 runtime policy。

验证：

- 冷启动服务恢复测试。
- 页面退出后服务仍按设置运行。
- 完整退出能够关闭 remote/EasyTier/native resources。
- 多次 start/stop 保持幂等。

## Phase 3：Platform Gateway 与 MainActivity 瘦身

目标：平台契约集中、可测试，MainActivity 只承担 Activity 职责。

建议提取：

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

要求：

- 通道名与方法名只在 gateway/handler 定义。
- 参数结构使用明确 model 或集中常量。
- 每个方法至少有 Dart contract test；关键通道增加 Kotlin 单元测试。
- 大块二进制数据继续使用原始 `Uint8List`，不得 JSON/Base64 化。

迁移顺序：

1. `browser_proxy` 的纯代理方法。
2. storage 与 external intent 方法。
3. `easytier_vpn`。
4. `remote_control`，最后迁移屏幕纹理和 Activity Result 相关逻辑。

## Phase 4：持久化与 Repository 边界

目标：存储实现不再决定 feature 依赖方向。

工作项：

1. 将代码概念 `BrowserDatabase` 改为 `AppDatabase`，数据库文件名暂时保持
   `browser_data.db`，避免数据迁移风险。
2. 为 history、favorites、downloads、AI chat 保持独立 repository。
3. 建立 `docs/data-ownership.md`，记录：
   - key/table/file
   - owner
   - schema/version
   - sensitive classification
   - backup/export policy
   - clear/delete policy
4. 为 SharedPreferences Store 增加统一 key 前缀和版本策略。
5. 明确 translation native history 与 Dart fallback 的单向同步规则。

验证：

- 从旧版本数据库升级。
- 统一备份往返。
- 清理各数据类别不会误删其他 feature 数据。

## Phase 5：Feature-first 目录迁移

目标：在契约稳定后解决文件发现和跨目录双向依赖。

建议顺序：

1. `ai`、`telegram`、`utilities`：边界小、迁移风险低。
2. `local_sharing`：统一公共 HTTP/path primitives 后移动。
3. `proxy`、`easytier`：已有明确 service 和 gateway。
4. `remote_control`：按 connection/screen/voice/protocol 移动，不改变 owner。
5. `browser`、`video`：最后移动，因为依赖最多且涉及 WebView keepAlive。

每个 feature 的推荐结构：

```text
features/<feature>/
├── presentation/       # pages/widgets
├── application/        # coordinators/use cases
├── domain/             # models/ports/policies
└── infrastructure/     # stores/platform/network implementations
```

小 feature 可以省略空目录。

移动规则：

- 一个提交只移动一个稳定模块。
- 移动提交不改类名和行为。
- 紧接着单独提交 import cleanup。
- `git diff` 应主要表现为 rename。

## Phase 6：Owner 收敛与复杂度控制

目标：减少 owner 的协调负担，而不是拆散资源所有权。

BrowserPage 可以继续抽出：

- browser runtime facade
- popup/auth/navigation facade
- media integration facade
- immutable browser view state projection

RemoteControlService 可以继续抽出：

- session state projection
- receiver/controller use cases
- diagnostics facade

禁止：

- 将 socket 字段分散到多个长期存活 service。
- coordinator 持有 BuildContext 或复制 owner 的 mutable state。
- 为了低于 400 行而创建大量 callback-heavy helper。

## 长期依赖规则

```text
app → features → core

presentation → application → domain
infrastructure → domain

禁止：
core → feature
feature A → feature B infrastructure
widget → page
domain → Flutter / MethodChannel / sqflite
```

允许的跨 feature 方式：

- domain port
- immutable event/model
- app-level coordinator
- shared core capability

## 每阶段合并检查表

- [ ] 当前分支直接基于 `main`。
- [ ] 没有混入无关 feature 修改。
- [ ] owner 和 source of truth 未改变或已明确迁移。
- [ ] 没有新增裸 MethodChannel。
- [ ] 没有新增目录级双向依赖。
- [ ] 持久化兼容旧版本。
- [ ] 热路径没有新增整页重建或持久化日志。
- [ ] 定向测试和完整 Flutter 测试通过。
- [ ] 涉及 native/Rust 时完成对应构建和协议测试。
- [ ] 文档同步更新。

## 明确不做的事情

- 不进行一次性全仓目录重排。
- 不全面替换状态管理方案。
- 不把独立本地服务强行合并为同一个 runtime。
- 不重写已经通过真实节点/设备验证的协议兼容代码。
- 不将 Android 系统能力重新实现到 Dart。
- 不因为架构重构改变用户导航和产品分类。

架构阶段之外的稳定性审计、性能实验和已完成历史计划归并见
[工程维护待办](maintenance-backlog.md)。后续不得再在 `temp/` 中维护平行 task 文档。
