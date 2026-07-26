# Browser / Remote 模块分类图

> 本文记录当前代码的责任归属。目标目录、依赖方向和迁移阶段见
> [架构设计](architecture.md) 与 [架构迁移路线](architecture-roadmap.md)。目标结构尚未
> 全部落地，不能把文档中的目标目录当作当前路径。

本文档记录 Browser 与 Remote 重构后的职责边界。它的目的不是替代代码结构，而是让后续维护者知道：哪些文件是 owner，哪些是流程组件，哪些只是纯 helper，以及什么情况下才值得继续拆分或迁目录。

## 总原则

- `BrowserPage` 和 `RemoteControlService` 仍是总调度 / 生命周期 owner。
- 已拆出的 coordinator/helper/service 应围绕功能边界维护，不为了行数继续拆。
- 如果新文件需要持有大量 owner 字段、`BuildContext`、`setState`、socket 字段或 MethodChannel 生命周期，说明边界还不稳定，不应抽出。
- 目录迁移应作为单独的纯移动变更执行，不与行为修改混在一起。

## Browser

### Owner

- `lib/pages/browser_page.dart`
  - 持有 Flutter lifecycle、`BuildContext`、`mounted`、`setState`。
  - 持有当前 WebView controller、地址栏 controller、active tab 状态和页面级 overlay 状态。
  - 串联 WebView callbacks、tab transitions、settings reload、auth/popup、proxy/navigation、下载/历史/收藏等跨功能流程。
  - 不建议继续按行数强拆。

### BrowserPage-local flows

这些文件只服务 `BrowserPage`，命名保持 `browser_page_*`，方便从 owner 跳转：

- 地址栏 / 输入：
  - `lib/pages/browser_page_address_bar_coordinator.dart`
  - `lib/pages/browser_page_input_resolver.dart`
  - `lib/pages/browser_page_address_sync.dart`
  - `lib/pages/browser_page_url_filter_helper.dart`
- Tab / session transitions：
  - `lib/pages/browser_page_tab_flow_coordinator.dart`
  - `lib/pages/browser_page_tab_transition_coordinator.dart`
  - `lib/pages/browser_page_tab_transition_helper.dart`
- WebView lifecycle / callback decisions：
  - `lib/pages/browser_page_webview_coordinator.dart`
  - `lib/pages/browser_page_webview_lifecycle_helper.dart`
  - WebView controller ownership remains in `BrowserPage`.
- Overlay / modal / shell UI composition：
  - `lib/pages/browser_page_overlay_state_manager.dart`
  - `lib/pages/browser_page_modal_coordinator.dart`
  - `lib/pages/browser_page_modal_actions.dart`
  - `lib/pages/browser_page_shell_widgets.dart`
- Settings / routing / external intents：
  - `lib/pages/browser_page_lifecycle_coordinator.dart`
  - `lib/pages/browser_page_settings_helper.dart`
  - `lib/pages/browser_page_route_handler.dart`
  - `lib/pages/browser_page_external_intent_helper.dart`
- Status / favorites / predicates：
  - `lib/pages/browser_page_status_coordinator.dart`
  - `lib/pages/browser_page_status_helper.dart`
  - `lib/pages/browser_page_favorite_helper.dart`
  - `lib/pages/browser_page_state_predicates.dart`
  - `lib/pages/browser_page_notifier_sync.dart`
  - `lib/pages/browser_page_site_security_helper.dart`

### Browser services

- Tab/session persistence and coordination:
  - `lib/browser/services/browser_tab_service.dart`
  - `lib/browser/services/browser_tab_coordinator.dart`
- Download flow:
  - `lib/browser/services/browser_download_service.dart`
  - `lib/browser/services/browser_download_coordinator.dart`
  - `lib/browser/services/browser_download_store.dart`
- Favorites/history/suggestions:
  - `lib/browser/services/browser_favorite_service.dart`
  - `lib/browser/services/browser_favorite_status_controller.dart`
  - `lib/browser/services/browser_favorite_status_tracker.dart`
  - `lib/browser/services/browser_favorite_action_coordinator.dart`
  - `lib/browser/services/browser_history_service.dart`
  - `lib/browser/services/browser_history_recorder.dart`
  - `lib/browser/services/browser_suggestion_service.dart`
- Settings/runtime/proxy/video:
  - `lib/browser/services/browser_settings_action_handler.dart`
  - `lib/browser/services/browser_settings_form_controller.dart`
  - `lib/browser/services/browser_settings_runtime_service.dart`
  - `lib/browser/services/browser_page_initializer.dart`
  - `lib/browser/services/browser_video_detection_coordinator.dart`
  - `lib/browser/services/browser_video_player_coordinator.dart`
  - `lib/features/proxy/infrastructure/proxy_service.dart`

### Browser files worth future extraction

Only consider these after their current behavior is stable and covered by tests/manual checks:

- `lib/browser/services/browser_backup_service.dart`
  - Candidate split: backup export, backup import, cookie/site-data export, file persistence.
- `lib/browser/widgets/floating_video_player_widget.dart`
  - Candidate split: gesture handling, control overlay, fullscreen layout, status/indicator UI.
- `lib/browser/widgets/browser_favorites_page.dart`
  - Candidate split: list body, search/filter, import/export actions, empty/error state.
- `lib/browser/widgets/settings/proxy_settings_section.dart`
  - Candidate split: proxy form, node list, latency/test actions, import/subscription controls.

## Remote / WebRTC

### Owner

- `lib/services/remote_control_service.dart`
  - Owns public Remote API, mode/state/config, socket fields, MethodChannel, connection/disconnect lifecycle, heartbeat and session-level sequencing.
  - Coordinates extracted screen, health, message routing, voice, connection and receiver startup components.
  - Do not split remaining socket/native ownership across multiple classes unless one class becomes the single obvious source of truth.

### Protocol and command layer

- `lib/features/remote_control/domain/remote_control_protocol.dart`
  - Message and command models.
- `lib/services/remote_control_command_helper.dart`
  - Native command execution helper.
- `lib/services/remote_control_status_bridge.dart`
  - MethodChannel status bridge.

### Connection / receiver lifecycle

- `lib/services/remote_control_connection_flow_coordinator.dart`
  - Controller retry / ready wait / reset timing.
- `lib/services/remote_control_connection_helper.dart`
  - Host normalization and port discovery.
- `lib/services/remote_control_lifecycle_helper.dart`
  - Controller socket connection setup.
- `lib/services/remote_control_receiver_startup_coordinator.dart`
  - Receiver native startup and server socket bind sequencing.
- `lib/services/remote_control_cleanup_helper.dart`
  - Resource cleanup callbacks.

### Screen stream and health

- `lib/services/remote_control_screen_frame_pipeline_coordinator.dart`
  - TCP chunks to parsed screen frames, SPS/PPS tracking and recovery gating.
- `lib/services/remote_control_screen_pipeline_helper.dart`
  - Frame parsing/coalescing helper.
- `lib/services/remote_control_screen_health_coordinator.dart`
  - Watchdog facade and key-frame recovery state.
- `lib/services/remote_control_watchdog_controller.dart`
  - Stall detection and bitrate adjustment logic.
- `lib/services/remote_control_recovery_helper.dart`
  - Recovery policy helpers.

### Message routing

- `lib/services/remote_control_message_router.dart`
  - Controller/receiver control-message buffering and dispatch.

### Voice / WebRTC

- `lib/services/remote_control_voice_coordinator.dart`
  - Remote voice session orchestration and microphone status flow.
- `lib/services/webrtc_voice_service.dart`
  - PeerConnection, audio routing, local/remote tracks, EasyTier-aware candidates and stats.
- `lib/features/remote_control/domain/webrtc_candidate_filter.dart`
  - Candidate classification and overlay host rewrite.
- `lib/services/webrtc_stats_summary.dart`
  - Stats formatting.

`webrtc_voice_service.dart` is still medium-large, but it was recently fixed for EasyTier voice and receiver-side gain. Avoid splitting it until LAN/EasyTier two-way voice has stayed stable for at least one testing cycle.

## Directory organization guidance

Current flat placement is acceptable because it minimizes import churn and keeps git history readable. If directory classification becomes necessary later, do it as a pure move-only change. Suggested shallow target:

```text
lib/pages/browser/
  browser_page.dart
  flows/
  webview/
  tabs/
  overlays/
  settings/

lib/services/remote_control/
  remote_control_service.dart
  connection/
  screen/
  voice/
  routing/
  protocol/
```

Rules for any future move:

1. Do not rename classes and move files in the same commit.
2. Do not move files while changing behavior.
3. Keep nesting shallow; one feature folder level is enough.
4. Run focused tests after import-only moves:

```bash
flutter test test/browser/
flutter test test/services/
flutter analyze lib/pages/browser_page.dart lib/services/remote_control_service.dart
```

## When further extraction is justified

Extract more only when at least one condition is true:

- A method cluster has clear inputs, outputs and private state that can be tested without owner internals.
- A section changes frequently and causes merge conflicts.
- New tests need logic that is currently trapped inside an owner class.
- A feature can move without passing long callback lists or many mutable owner fields.

Do not extract merely because a file is over a target line count.
