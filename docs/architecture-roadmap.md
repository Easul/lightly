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

### 测试基线

迁移路线多次要求“contract test 通过”，但这些测试大部分尚不存在，因此“补齐测试脚手架”本身
就是迁移的前置工作，不能隐含在移动提交里。执行任何 Phase 前先重新测量当前覆盖：

```bash
flutter test              # 现有 Dart 测试
cargo test --manifest-path rust/proxy-core/Cargo.toml
find android -name '*Test.kt' | wc -l   # 当前 Kotlin 单测数量
```

- Dart 侧目前主要覆盖 proxy、部分 browser 服务，尚无系统性的 platform channel contract test。
- Kotlin 侧几乎没有 channel handler 单测，Phase 3 的“每个方法至少一个测试”需当作独立工作量排期。
- 每个 Phase 开始前把上述实际数字写进对应 PR 描述，不要复用本文历史数字当事实。

## 迁移原则

1. **先契约，后移动。** 先定义 owner、接口、状态和测试，再迁目录。
2. **先横向基础设施，后 feature 重排。** 生命周期和 platform gateway 优先于文件分类。
3. **一次只改变一个维度。** 行为、依赖反转、文件移动、命名迁移分别提交。
4. **兼容性路径冻结。** VLESS、Telegram SOCKS5、EasyTier、远控和 WebView keepAlive
   在对应迁移阶段不得顺带重写。
5. **应用始终可发布。** 每阶段完成后必须能通过现有测试与 Release 构建。

## Phase 0：架构契约与文档

状态：**已完成（2026-07-26）**

交付物：

- 当前/目标架构文档。
- 模块 owner、依赖方向和设计原则。
- 生命周期、持久化和平台通道基线。
- 本迁移路线。
- `docs/data-ownership.md` 的**初版**数据 owner 清单（key/table/file、owner、schema/version、
  敏感级别、备份、清除策略）。这是纯文档、零代码风险，必须在移动任何代码前存在，让后续每个
  Phase 都能对照它验证"没有破坏隐性数据合同"。Phase 4 只负责让代码结构追平这张表，而不是从头创建它。

完成标准（exit criteria）：

- 文档不再描述已经删除的 Dart VLESS/local mixed proxy 路径。
- 新代码评审可以引用明确的边界规则。
- `docs/data-ownership.md` 存在，且覆盖当前所有 SQLite 表、SharedPreferences key 组和 native store。
- 代理路由/bypass 正确性合同已在 `AGENTS.md` 有明确条目（见 `## Proxy Bypass / Routing Correctness`），
  后续 proxy feature 迁移必须引用它。

## Phase 1：Composition Root 与依赖接口

状态：**已完成（2026-07-26）**

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
4. 抽出跨 feature ports，每个 port 都对准一个当前真实存在的违规依赖，而不是凭空设计接口：
   - `LocalProxyEndpointProvider` —— 消灭 `Telegram → ProxyService` 的直接依赖，Telegram 只拿本地
     SOCKS5 端点，不再感知代理实现。
   - `AppDatabaseProvider` —— 消灭 `AI history → BrowserDatabase` 的直接依赖，AI 通过 provider 拿到
     数据库句柄，不再依赖"浏览器"命名的类。
   - `SharedDownloadsAccess` —— 统一下载/备份/日志导出对共享目录的访问，避免多 feature 各自拼路径。
   - `RuntimeLogger` —— 让各 feature 记日志时不再反向依赖具体日志服务实现。

   每个 port 必须同时提交"旧的直接依赖已改为依赖 port"的证据，否则 port 只是"设计了但没人用"。

非目标：

- 不替换所有 singleton。
- 不引入新的全局状态管理框架。
- 不移动 BrowserPage 或 RemoteControlService。

验证：

- `flutter test`
- 路由与默认页 Widget 测试
- service 注入单元测试

完成标准（exit criteria）：

- `lib/app/` 存在且 `main.dart` 只负责 bootstrap，不再直接组装分散的全局 service。
- 上述四个 port 已定义，且至少 `LocalProxyEndpointProvider` 与 `AppDatabaseProvider` 已被
  Telegram 和 AI 实际使用，`grep` 不再出现 `Telegram → ProxyService`、`AI → BrowserDatabase` 的直接构造。

回退（rollback）：

- 本阶段全部是新增文件 + 依赖注入点替换，不改行为。任一提交可单独 `git revert`，port 未被使用时
  删除接口文件即可，不涉及数据或协议。

## Phase 2：统一 Runtime 生命周期

状态：**代码完成，待真机验收**

实施进度（2026-07-26）：

- 已将 simple file manager 持久化启动移出 `main.dart`。
- 已将远控/EasyTier 的退出与远控启动 EasyTier 策略迁入 `AppRuntimeCoordinator`。
- `AppLifecycleManager` 已只保留 Flutter lifecycle 转发和兼容委托，不再持有具体 service。
- local HTTP、clipboard、proxy runtime 的冷启动恢复、设置应用和关闭已迁入
  `BrowserRuntimeCoordinator`，由 `AppRuntimeCoordinator` 统一调用。
- Settings、BrowserPage、EasyTier、Clipboard 和 Simple File Manager 页面已改为提交策略命令；
  service 仍是运行状态 source of truth。
- `RemoteControlService` 的 receiver host cleanup 不再直接停止 EasyTier，而是回调应用 runtime 策略。
- 待验收：真机完整退出后通过 `adb shell dumpsys` 确认无 capture/VPN 前台服务残留。

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

`AppLifecycleManager` 与 `AppRuntimeCoordinator` 的关系（避免两者职责重叠）：

- `AppRuntimeCoordinator` 是唯一的**策略**入口：决定"在什么条件下启动/停止哪个 runtime"。
- `AppLifecycleManager` 降级为纯 **Flutter lifecycle 事件转发器**：只把 `paused`/`resumed`/`detached`
  等回调转交给 coordinator，不再自己直接决定关闭远控或 EasyTier。
- 迁移完成后 `AppLifecycleManager` 不得再持有任何 service 的 stop 逻辑；如果它变空则删除，退出清理
  统一由 `shutdownAll()` 收口。

迁移顺序：

1. Simple file manager startup 从 `main.dart` 移入 coordinator。
2. Local HTTP 与 clipboard auto-start 从 BrowserPage 初始化移入 coordinator。
3. Proxy settings runtime 应用移入 coordinator，但 WebView proxy attach 仍通过 browser port。
4. 把 `AppLifecycleManager` 现有退出逻辑迁入 `shutdownAll()`，并将其改为事件转发。
5. EasyTier/remote-control 复用同一 runtime policy。

验证：

- 冷启动服务恢复测试。
- 页面退出后服务仍按设置运行。
- 完整退出能够关闭 remote/EasyTier/native resources。
- 多次 start/stop 保持幂等。

完成标准（exit criteria）：

- simple file manager、local HTTP、clipboard、proxy runtime、EasyTier、remote control 六个 runtime 的
  启动/停止调用都经过 `AppRuntimeCoordinator`，页面里不再有直接 `.start()/.stop()` 散点。
- `AppLifecycleManager` 不再包含任何具体 service 的关闭逻辑。
- 应用完整退出后，`adb shell dumpsys` 下无残留 capture/VPN 前台服务。

回退（rollback）：

- coordinator 是新增的编排层，内部仍调用现有 service 方法。若行为异常，可先让页面/`main.dart` 恢复
  直接调用（revert 对应移动提交），coordinator 保留但不接线，不影响 service 自身实现。

## Phase 3：Platform Gateway 与 MainActivity 瘦身

状态：**代码已完成（2026-07-26），待真机验收**

目标：平台契约集中、可测试，MainActivity 只承担 Activity 职责。

已交付：

- `browser_proxy` 已拆为 browser proxy、storage access、external intent 与悬浮模式 handler/gateway。
- `easytier_vpn` 已由 `EasyTierPlatformGateway` / `EasyTierChannelHandler` 持有，包含权限与监控生命周期。
- `remote_control` 已由 `RemoteControlPlatformGateway` / `RemoteControlChannelHandler` 持有，
  屏幕帧保持 `Uint8List` / `ByteArray` 直传。
- `MainActivity` 不再直接注册 MethodChannel handler，保留 Activity Result 与生命周期委派。
- Dart contract tests 覆盖全部迁移方法，关键 Kotlin handler 具备参数、权限状态和二进制路径单测。

建议提取：

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

完成标准（exit criteria）：

- `MainActivity` 不再直接注册任何 `setMethodCallHandler`；三个目标通道全部由独立 handler 承载。
- 平台通道清单（架构文档表格）中 `browser_proxy`、`easytier_vpn`、`remote_control` 的
  Android Owner 不再是 `MainActivity`。
- 每个已迁移方法至少有一个 Dart contract test，`remote_control` 二进制帧路径仍是 `Uint8List` 直传。

回退：每个通道一次提取一个提交，先加 handler + gateway 并让 `MainActivity` 委派，再删除
`MainActivity` 内旧实现。回退 = revert 后一步，委派仍可用，运行行为不变。

## Phase 4：持久化与 Repository 边界

状态：**已完成（2026-07-26）**

实施结果：

- 代码 owner 已从 `BrowserDatabase` 改为 `AppDatabase`，物理文件仍是 `browser_data.db`，
  schema version 仍是 `4`，表名和 SQL 未改变。
- history、favorites、downloads 继续由各自 repository/store 持有；AI chat 继续通过
  `AppDatabaseProvider` 获取共享句柄，并持有自己的表名。
- 新增 v3 到 v4 升级与数据类别隔离清理合同测试。
- `docs/data-ownership.md` 已对齐真实 owner，并明确 SharedPreferences 兼容策略：冻结现有
  物理 key；新 key 使用 feature 前缀；破坏性格式变化使用带版本的新 key 和显式迁移。
- Android 翻译历史保持 native store 为 source of truth，Dart fallback 仅用于非 Android，
  不做自动双向合并。

目标：存储实现不再决定 feature 依赖方向。

工作项：

1. 将代码概念 `BrowserDatabase` 改为 `AppDatabase`，数据库文件名暂时保持
   `browser_data.db`，避免数据迁移风险。此步为纯 rename：不改 schema、不改建表 SQL、
   不改序列化格式，仅改类名与 import。
2. 为 history、favorites、downloads、AI chat 保持独立 repository。
3. 按 Phase 0 已建立的 `docs/data-ownership.md` 补全实际实现细节，并让 AI chat 通过
   `AppDatabaseProvider`（Phase 1 引入的 port）而非直接依赖 `BrowserDatabase`。
4. 为 SharedPreferences Store 建立统一 key 前缀和版本策略；已有物理 key 保持兼容，
   不因架构重构改名。
5. 明确 translation native history 与 Dart fallback 的单向同步规则。

完成标准（exit criteria）：

- 代码中不再出现 `BrowserDatabase` 类名（数据库文件名仍为 `browser_data.db`）。
- AI/history 不再直接 import 浏览器数据库实现，改经 `AppDatabaseProvider`。
- `docs/data-ownership.md` 的每一行都对应到真实 owner。

回退：改名提交是纯机械 rename，回退 = revert 单个 commit，数据库文件与 schema 全程未动，
无数据迁移风险。

验证：

- 从旧版本数据库升级。
- 统一备份往返。
- 清理各数据类别不会误删其他 feature 数据。

## Phase 5：Feature-first 目录迁移

状态：**进行中（2026-07-26）**

已完成的纯移动批次：

- `lib/ai_tools/` → `lib/features/ai/`
- `lib/telegram_checkin/` → `lib/features/telegram/`
- `lib/calculator/` → `lib/features/calculator/`
- `lib/game_2048/` → `lib/features/game_2048/`
- local sharing 公共局域网地址解析器 → `lib/core/network/`
- Simple File Manager、Clipboard、Local HTTP → `lib/features/local_sharing/`
- EasyTier domain/application/infrastructure 与独立 widgets → `lib/features/easytier/`
- proxy domain/application/infrastructure、runtime owner 与 platform gateway → `lib/features/proxy/`
- remote-control domain contracts、纯 application policies 与 platform gateway →
  `lib/features/remote_control/`

以上移动批次只移动模块并更新 import；存储 key、数据库表、网络协议和 runtime owner 均未改变。
local sharing 移动前已先把日志依赖反转到 `RuntimeLogger`，并将 Local HTTP 输入收窄为独立 config；
proxy 移动前同样将日志反转到 `RuntimeLogger`，并以不可变 `ProxyConfiguration` 隔离
`BrowserSettings`。EasyTier 设置页因仍编排 browser/local-sharing/app runtime 而暂留 `lib/pages/`；
remote-control socket owner、screen/voice infrastructure 与 presentation，以及 browser/video
继续按下列顺序渐进处理。

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
