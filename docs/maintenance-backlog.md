# Lightly 工程维护待办

[English](maintenance-backlog.en.md)

## 定位

本文归并了历史临时任务计划中仍有维护价值的内容。它不是承诺排期，也不表示历史问题仍然
存在；执行前必须重新审计当前代码、测试和真实设备基线。

架构性工作以 [架构迁移路线](architecture-roadmap.md) 为主，本文只记录可以独立实施的工程
质量候选项。

## 已完成或已被正式文档吸收

- BrowserPage service wiring、tab flow、shell/widget 与 Local HTTP handler 已完成多轮拆分。
- SettingsPage 的低风险 section/action 拆分已基本完成。
- RemoteControlSessionPage、连接、消息路由、屏幕 pipeline、watchdog 等 seam 已提取。
- ProxyService mapper/latency/error 逻辑和 Rust VLESS transport/handshake 已完成结构拆分。
- 多 ABI 构建、版本标签、Release 混淆与产物检查由 `scripts/build_multi_abi.sh` 统一。
- EasyTier profile、peer 信息、网络状态复制和本地服务暴露已有当前实现与正式文档。
- 旧 Dart VLESS / local mixed proxy 已删除，不能作为后续重构基线。
- 旧“固定 UDP 音频端口”远控方案已由 WebRTC voice 取代，现状见
  [远程控制架构](remote-control-architecture.md)。

## 高优先级：先审计再修复

### 异步生命周期安全

- 审计 `await`、timer、stream callback 之后的 Widget 更新是否有 `mounted` 保护。
- 审计所有手工 `StreamSubscription`、periodic timer 和 listener 是否对称释放。
- 审计 Activity 销毁时 pending permission/result callback 是否清空。
- 不做全仓机械替换；以可复现问题和明确 owner 为单位提交。

### 错误处理完整性

- 审计 Rust 外部输入/网络失败路径中的 `unwrap()`/`expect()`，测试代码和不可失败常量除外。
- 审计空 `catch` 与关键 `unawaited()`，只为用户可诊断的失败增加经过脱敏的日志。
- 不把帧、手势、WebView progress、代理 packet 等热路径错误持续写入 `runtime.log`。

### FFI 与 native 初始化幂等

- 确认 proxy-core panic hook、logger 和 JNI/FFI 初始化只能注册一次。
- 代理 stop/start 只重建 runtime，不重复安装全局 hook。
- 平台通道 Activity Result 与 service reference 必须在销毁/重建时可恢复。

## 中优先级：架构路线内实施

### App runtime coordinator

代码收口已完成：simple file manager、local HTTP、clipboard、proxy、EasyTier 和 remote control
的应用级策略经过 coordinator，service 仍持有实际资源。剩余项是 Phase 2 的真机退出残留验收。

### MainActivity 瘦身

依次提取 browser proxy/storage/intent、EasyTier、remote-control handler。先建立 typed Dart
gateway 和 contract test，再移动 Kotlin 实现。

### 数据 ownership

- 将代码概念 `BrowserDatabase` 迁为 `AppDatabase`，暂不改数据库文件名。
- 建立数据 owner、schema、敏感级别、备份、清除策略清单。
- 明确 native translation history 与 Dart fallback 的单向同步。

### 大 owner 的后续收敛

- BrowserPage：只继续提取稳定的 navigation/popup/runtime facade，不移动 WebView owner。
- RemoteControlService：audio transport 是剩余高风险 seam，需在 WebRTC 覆盖充分后处理。
- Native video：初始化、手势和下载 workflow 可按行为不变原则独立提取。

## 低优先级：必须以数据驱动

### UI 局部刷新

只在 profiling 证明整页重建有实际开销时，将高频设置组迁到 `ValueNotifier`。不要仅根据
`setState()` 数量判断，也不进行全局状态管理迁移。

### 缓冲与分配优化

- Rust buffer pool、`BytesMut` 复用和减少拷贝必须先有 allocation/throughput 基线。
- 不能为了“零拷贝”改变 VLESS first payload、SOCKS5 boundary 或 half-close 语义。
- Dart LRU helper 只有在当前实现仍重复且行为可证明一致时再抽取。

### 常量集中

进度 `5%`、滚动 `24px`、视频检测 `180ms` 等值已经是兼容/性能合同。只有在能提高可发现性
且不造成跨 feature 巨型 constants 文件时，才迁移为命名常量。

## 独立产品提案

原生 Android EasyTier 摄像头/双向音视频项目不属于 Lightly 当前 feature-first 迁移，已单独
保存在 [Native EasyTier Camera Remote Proposal](proposals/native-easytier-camera-remote.md)。

## 执行检查

- 重新测量，不复用历史行数、失败测试数或 APK 大小作为当前事实。
- 一个分支只处理一个清晰问题，直接基于 `main`。
- 先补测试或复现，再修改高风险 lifecycle/protocol 代码。
- 涉及 WebView、proxy、EasyTier、remote control 时遵循 `AGENTS.md` 专项规则。
- 完成后更新本文状态或删除已无价值的候选项，避免再次产生临时 task 文档。
