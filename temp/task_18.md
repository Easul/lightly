# Task 18: Browser / Remote 流程化规范重构

> 优先级: 🟡 中 | 影响范围: Browser / Remote Control 架构
> 原则: 渐进式、可回滚、每次只迁移一个 flow；不引入通用 workflow engine；不改变任何现有行为。

## 总目标

把 `BrowserPage` 与 `RemoteControlService` 从“大类中串联大量步骤”逐步规范为：

```text
Page / Service = 总调度与生命周期所有者
Flow / Coordinator = 命名业务流程
Helper = 纯逻辑 / 小工具
Result = 明确流程输出
StateMachine = 复杂异步阶段管理
```

## 硬性约束

- 不为了行数强拆；只有当边界清晰、可测试、能降低认知负担时才拆。
- Browser 中 `BuildContext`、`mounted`、`setState`、WebView controller、Flutter lifecycle 仍由 `BrowserPage` 持有。
- Remote 中 socket 总生命周期、public API、全局 mode/state/config 仍由 `RemoteControlService` 持有，直到对应 coordinator 成熟后再局部迁移。
- 不抽象 VLESS / SOCKS5 / EasyTier native / WebRTC fragile protocol 细节。
- 每个子任务完成后必须运行相关测试；触碰 WebView / proxy / remote 核心时必须补充手动验证清单。

---

## Phase 0: 安全网与基线

### 18.0.1 建立重构基线

- [x] 确认工作区干净。
- [x] 记录当前大文件行数。
- [x] 运行当前 browser / remote 相关测试作为基线。
- [x] 如测试已有失败，记录为既有问题，不在重构中顺手修。

基线结果（2026-05-28）：

- `flutter test test/browser/` 通过。
- `flutter test test/services/` 通过。
- `flutter analyze lib/pages/browser_page.dart lib/services/remote_control_service.dart` 通过。

验证命令：

```bash
flutter test test/browser/
flutter test test/services/
flutter analyze lib/pages/browser_page.dart lib/services/remote_control_service.dart
```

---

## Phase 1: Remote 低风险流程化试点

### 18.1.1 抽 `RemoteControlScreenFramePipelineCoordinator`

目标：把屏幕帧 chunk → buffer → parse → SPS/PPS → coalesce → frame 输出流程从 `RemoteControlService` 中抽出。

状态归属：

- `_screenDataBuffer`
- `_latestRemoteSps`
- `_latestRemotePps`
- 与屏幕帧拼包/合帧直接相关的状态

保留在 `RemoteControlService`：

- `_screenFrameController.add(...)`
- watchdog / bitrate 调整调用
- socket listener 生命周期

完成标准：

- [x] 新增 coordinator，公开 `handleIncomingData(Uint8List)` / `reset()`。
- [x] `RemoteControlService._handleScreenDataRaw` 变成薄包装。
- [x] 新增/更新单测覆盖：完整帧、半包、多个帧、SPS/PPS 更新、delta coalesce。
- [x] `flutter test test/services/` 通过。

验证结果（2026-05-28）：

- `flutter analyze lib/services/remote_control_service.dart lib/services/remote_control_cleanup_helper.dart lib/services/remote_control_screen_frame_pipeline_coordinator.dart test/services/remote_control_screen_frame_pipeline_coordinator_test.dart` 通过。
- `flutter test test/services/remote_control_screen_frame_pipeline_coordinator_test.dart test/services/` 通过。

### 18.1.2 抽 `RemoteControlScreenHealthCoordinator`

目标：把屏幕帧健康检查、watchdog、key frame recovery、bitrate 调整流程命名化。

完成标准：

- [x] coordinator 持有 watchdog timer 与 frame arrival 状态。
- [x] `RemoteControlService` 只提供回调：request key frame / update bitrate。
- [x] 测试覆盖 stall 后 key frame 请求、冷却时间、bitrate 调整阈值。

验证结果（2026-05-28）：

- `flutter analyze lib/services/remote_control_service.dart lib/services/remote_control_cleanup_helper.dart lib/services/remote_control_screen_frame_pipeline_coordinator.dart lib/services/remote_control_screen_health_coordinator.dart test/services/remote_control_screen_frame_pipeline_coordinator_test.dart test/services/remote_control_screen_health_coordinator_test.dart` 通过。
- `flutter test test/services/remote_control_screen_frame_pipeline_coordinator_test.dart test/services/remote_control_screen_health_coordinator_test.dart test/services/` 通过。

### 18.1.3 抽 `RemoteControlMessageRouter`

目标：把 control socket bytes → line buffer → JSON decode → typed route 的流程拆出。

完成标准：

- [x] router 持有 controller/receiver control buffer。
- [x] WebRTC signal / heartbeat / status / native command 路由保持行为不变。
- [x] 测试覆盖粘包、半包、receiver heartbeat/status/action 路由。

验证结果（2026-05-28）：

- `flutter analyze lib/services/remote_control_service.dart lib/services/remote_control_cleanup_helper.dart lib/services/remote_control_message_router.dart test/services/remote_control_message_router_test.dart` 通过。
- `flutter test test/services/remote_control_message_router_test.dart test/services/` 通过。

---

## Phase 2: Browser 低风险流程化

### 18.2.1 抽 `BrowserPageAddressBarCoordinator`

目标：把地址栏输入 → URL/search 解析 → native video bypass → favorites/WebView load plan 规范为 result flow。

完成标准：

- [x] coordinator 返回 `BrowserAddressBarPlan`，不直接 `setState`。
- [x] `BrowserPage._loadAddress` 只执行 plan。
- [x] 测试覆盖 URL、搜索词、YouTube native player、favorites page 切换。

验证结果（2026-05-28）：

- `flutter analyze lib/pages/browser_page.dart lib/pages/browser_page_address_bar_coordinator.dart test/browser/browser_page_address_bar_coordinator_test.dart` 通过。
- `flutter test test/browser/browser_page_address_bar_coordinator_test.dart test/browser/` 通过。

### 18.2.2 抽 `BrowserPageTabTransitionCoordinator`

目标：把 open/switch/close/closeAll tab 的步骤顺序集中。

完成标准：

- [x] coordinator 输出明确 transition flow。
- [x] WebView controller ownership 仍在 `BrowserPage`。
- [x] 保持 keepAlive trim、address sync、favorite status refresh 顺序不变。

验证结果（2026-05-28）：

- `flutter analyze lib/pages/browser_page.dart lib/pages/browser_page_tab_transition_coordinator.dart test/browser/browser_page_tab_transition_coordinator_test.dart` 通过。
- `flutter test test/browser/browser_page_tab_transition_coordinator_test.dart test/browser/browser_page_tab_transition_helper_test.dart test/browser/browser_page_tab_flow_coordinator_test.dart test/browser/` 通过。

### 18.2.3 抽 `BrowserPageWebViewLifecycleCoordinator`

目标：把 WebView create/load/progress/title/history/error/scroll callback 的决策流程集中。

完成标准：

- [x] 保持 progress 5% threshold、scroll 24px threshold、loading state 稳定规则不变。
- [x] 不引入高频 `setState()`。
- [x] browser 全量测试通过。
- [ ] 手动验证打开页面、tab 切换、find-in-page、popup auth、HTTP auth。

实现说明（2026-05-28）：

- 先做保守命名化：将 `BrowserPage` build 中的 WebView 匿名 callback 下沉为命名 handler。
- 不迁移 WebView controller ownership，也不改变 setState / progress / history / error 行为。
- 复用既有 `BrowserPageWebViewCoordinator` 测试覆盖决策逻辑。

验证结果（2026-05-28）：

- `flutter analyze lib/pages/browser_page.dart` 通过。
- `flutter test test/browser/` 通过。

---

## Phase 3: Remote 中风险流程化

### 18.3.1 抽 `RemoteControlVoiceFlow`

目标：集中远程麦克风状态、WebRTC voice prepare/stop、signal 转发的流程。

完成标准：

- [x] controller / receiver 语音角色明确。
- [x] remote microphone toggle UI 状态同步不回退。
- [ ] 真机验证 WebRTC 双向语音、耳机/蓝牙路由。

实现说明（2026-05-28）：

- 抽出 `RemoteControlVoiceCoordinator` 管理 WebRTC prepare、signal routing、本地音频启停和远端麦克风状态。
- `RemoteControlService` 仍保留 socket、public API、target host 与整体生命周期主控权。

验证结果（2026-05-28）：

- `flutter analyze lib/services/remote_control_service.dart lib/services/remote_control_voice_coordinator.dart test/services/remote_control_voice_coordinator_test.dart` 通过。
- `flutter test test/services/remote_control_voice_coordinator_test.dart test/services/` 通过。

### 18.3.2 抽 `RemoteControlConnectionCoordinator`

目标：集中 controller connect retry、ready completer、control/screen socket 建立流程。

完成标准：

- [x] retry 时序不变。
- [x] proxy 连接路径不变。
- [ ] disconnect/reconnect 后 socket/timer 无残留。
- [ ] 真机验证 LAN / EasyTier 10.126 / 内置代理屏幕控制。

实现说明（2026-05-29）：

- 抽出 `RemoteControlConnectionFlowCoordinator` 管理 controller 连接尝试、ready 等待、失败 reset 与 retry delay。
- `RemoteControlService` 仍保留 socket 字段、public API、mode/state/config、native MethodChannel 和实际 socket 建立回调。
- `RemoteControlService._markConnectionReady()` 改为委托 coordinator，ready 来源仍保持为 screen frame / `screen_info`。

验证结果（2026-05-29）：

- `flutter analyze lib/services/remote_control_service.dart lib/services/remote_control_connection_flow_coordinator.dart test/services/remote_control_connection_flow_coordinator_test.dart` 通过。
- `flutter test test/services/remote_control_connection_flow_coordinator_test.dart test/services/` 通过。

### 18.3.3 抽 `RemoteControlReceiverCoordinator`

目标：集中 receiver native startup、server socket bind、client accept、rollback。

完成标准：

- [x] receiver 启动失败能 rollback。
- [x] server socket 关闭行为不变。
- [ ] 真机验证被控端启动、控制端连接、断开重连。

实现说明（2026-05-29）：

- 抽出 `RemoteControlReceiverStartupCoordinator` 管理 receiver native 启动、control/screen server bind 顺序，以及失败 rollback。
- `RemoteControlService` 仍保留 `ServerSocket` 字段、socket listen 回调、state/config/mode 与 native MethodChannel 调用细节。

验证结果（2026-05-29）：

- `flutter analyze lib/services/remote_control_service.dart lib/services/remote_control_receiver_startup_coordinator.dart test/services/remote_control_receiver_startup_coordinator_test.dart` 通过。
- `flutter test test/services/remote_control_receiver_startup_coordinator_test.dart test/services/` 通过。

---

## Phase 4: 收尾与目录规范化

### 18.4.1 评估目录迁移

候选结构：

```text
lib/browser/page/
lib/browser/workflows/
lib/browser/coordinators/
lib/remote_control/workflows/
lib/remote_control/coordinators/
lib/remote_control/protocol/
```

仅当前面 flow 稳定后再做，避免大量 import diff 干扰行为审查。

评估结论（2026-05-29）：

- 本轮不执行目录迁移；当前新增 coordinator 已按既有 `lib/pages/` / `lib/services/` 风格落位。
- 大规模 import 迁移会制造大量无行为 diff，且无法替代真机回归验证。

### 18.4.2 文档化回归清单

- [x] `docs/browser_regression_checklist.md`
- [x] `docs/remote_control_regression_checklist.md`
- [x] `docs/release_build.md`

---

## 全部完成标准

- [x] Browser 关键 flow 有明确 coordinator/plan/result。
- [x] Remote 关键 flow 有明确 coordinator/state ownership。
- [x] `BrowserPage` 仍保留 Flutter lifecycle 主控权。
- [x] `RemoteControlService` 仍保留 public API 与总生命周期主控权。
- [x] 所有相关测试通过。
- [ ] 手动验证 browser / remote / proxy / WebRTC / EasyTier 关键路径。
- [x] release 多 ABI 构建成功。

Release 构建结果（2026-05-29）：

- `bash scripts/build_multi_abi.sh` 通过。
- 版本标签：`v1.0.5+460843`。
- Android versionCode：`5140`。
- 产物：
  - `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
  - `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
