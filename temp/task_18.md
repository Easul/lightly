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

- [ ] router 持有 controller/receiver control buffer。
- [ ] WebRTC signal / heartbeat / status / native command 路由保持行为不变。
- [ ] 测试覆盖粘包、半包、非法 JSON、WebRTC signal 路由。

---

## Phase 2: Browser 低风险流程化

### 18.2.1 抽 `BrowserPageAddressBarCoordinator`

目标：把地址栏输入 → URL/search 解析 → native video bypass → favorites/WebView load plan 规范为 result flow。

完成标准：

- [ ] coordinator 返回 `BrowserAddressBarPlan`，不直接 `setState`。
- [ ] `BrowserPage._loadAddress` 只执行 plan。
- [ ] 测试覆盖 URL、搜索词、YouTube native player、favorites page 切换。

### 18.2.2 抽 `BrowserPageTabTransitionCoordinator`

目标：把 open/switch/close/closeAll tab 的步骤顺序集中。

完成标准：

- [ ] coordinator 输出明确 transition plan。
- [ ] WebView controller ownership 仍在 `BrowserPage`。
- [ ] 保持 keepAlive trim、address sync、favorite status refresh 顺序不变。

### 18.2.3 抽 `BrowserPageWebViewLifecycleCoordinator`

目标：把 WebView create/load/progress/title/history/error/scroll callback 的决策流程集中。

完成标准：

- [ ] 保持 progress 5% threshold、scroll 24px threshold、loading state 稳定规则不变。
- [ ] 不引入高频 `setState()`。
- [ ] browser 全量测试通过。
- [ ] 手动验证打开页面、tab 切换、find-in-page、popup auth、HTTP auth。

---

## Phase 3: Remote 中风险流程化

### 18.3.1 抽 `RemoteControlVoiceFlow`

目标：集中远程麦克风状态、WebRTC voice prepare/stop、signal 转发的流程。

完成标准：

- [ ] controller / receiver 语音角色明确。
- [ ] remote microphone toggle UI 状态同步不回退。
- [ ] 真机验证 WebRTC 双向语音、耳机/蓝牙路由。

### 18.3.2 抽 `RemoteControlConnectionCoordinator`

目标：集中 controller connect retry、ready completer、control/screen socket 建立流程。

完成标准：

- [ ] retry 时序不变。
- [ ] proxy 连接路径不变。
- [ ] disconnect/reconnect 后 socket/timer 无残留。
- [ ] 真机验证 LAN / EasyTier 10.126 / 内置代理屏幕控制。

### 18.3.3 抽 `RemoteControlReceiverCoordinator`

目标：集中 receiver native startup、server socket bind、client accept、rollback。

完成标准：

- [ ] receiver 启动失败能 rollback。
- [ ] server socket 关闭行为不变。
- [ ] 真机验证被控端启动、控制端连接、断开重连。

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

### 18.4.2 文档化回归清单

- [ ] `docs/browser_regression_checklist.md`
- [ ] `docs/remote_control_regression_checklist.md`
- [ ] `docs/release_build.md`

---

## 全部完成标准

- [ ] Browser 关键 flow 有明确 coordinator/plan/result。
- [ ] Remote 关键 flow 有明确 coordinator/state ownership。
- [ ] `BrowserPage` 仍保留 Flutter lifecycle 主控权。
- [ ] `RemoteControlService` 仍保留 public API 与总生命周期主控权。
- [ ] 所有相关测试通过。
- [ ] 手动验证 browser / remote / proxy / WebRTC / EasyTier 关键路径。
- [ ] release 多 ABI 构建成功。
