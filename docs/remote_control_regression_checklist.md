# Remote Control 回归验证清单

本清单用于远程控制、屏幕流、WebRTC 语音、EasyTier / 内置代理连接路径相关改动后的人工验证。自动测试只能证明流程组件行为，不等于真机链路通过。

## 自动验证

```bash
flutter analyze lib/services/remote_control_service.dart
flutter test test/services/
```

如果触碰 Android 原生 capture / accessibility / audio 代码，还需要构建 APK 并在真机验证。

## Receiver 启动与回滚

- [ ] 在被控端打开设置中的远程控制入口。
- [ ] 启动 receiver 后 UI 显示可连接地址和端口。
- [ ] control server 与 screen server 都能正常监听。
- [ ] 禁用屏幕时只启动 control 相关路径，不要求 screen socket。
- [ ] 模拟端口占用或权限失败时，启动失败后 native 服务、server socket、音频、watchdog 被清理。
- [ ] 再次启动 receiver 不因上一次失败残留而失败。

## Controller 连接

- [ ] LAN IP 连接 receiver 成功。
- [ ] EasyTier `10.126.*` 地址连接 receiver 成功。
- [ ] 内置代理模式连接 receiver 成功，且语音按设计禁用。
- [ ] 连接失败时会重试，最终失败后状态变为 error。
- [ ] receiver 发出 `screen_info` 或首帧后 controller 才进入 connected。
- [ ] 断开后重连成功，socket/timer/watchdog 无残留。

## 屏幕流

- [ ] 首屏能显示，不停留黑屏。
- [ ] 红米等高分辨率机型如果全尺寸 AVC 配置失败，会降级到兼容尺寸并继续出帧。
- [ ] 日志中能看到实际捕获尺寸，并且 controller 侧 `screen_info` 使用对应 `captureWidth` / `captureHeight`。
- [ ] 横竖屏或分辨率变化后画面尺寸更新。
- [ ] delta frame 连续播放流畅。
- [ ] key frame request / recovery 后画面可恢复。
- [ ] 快速断开 screen socket 不导致服务崩溃。

## 远程输入

- [ ] 点击、长按、滑动都能注入到被控端。
- [ ] 返回 / Home / 最近任务等全局动作正常。
- [ ] Android 13+ 被控端可通过 controller 侧文本输入发送文字。
- [ ] 浮动控制尾巴可拖动，且不长期遮挡主要画面。

## WebRTC 语音

- [ ] Controller 听 Receiver 声音正常。
- [ ] Receiver 麦克风开关状态能同步到 Controller。
- [ ] Controller 说话能在 Receiver 端听到。
- [ ] EasyTier 连接下连续讲话 1 分钟以上，Receiver 端不出现长期静音；如出现短暂停滞，日志应有 `webrtc-remote-audio-stall` 并自动恢复。
- [ ] EasyTier 网络短暂波动后，远控控制/屏幕通道和 WebRTC 语音能自动重连或重建。
- [ ] 耳机 / 蓝牙路由下声音方向正确。
- [ ] 内置代理连接模式不提供 WebRTC 对话，并且 UI/日志符合设计。
- [ ] 断开远控后 WebRTC session 和本地音频 track 被释放。

## 剪贴板与状态消息

- [ ] 心跳消息持续更新，不误判断线。
- [ ] 剪贴板同步消息能双向传递。
- [ ] `port_config` 状态能更新 controller 侧端口配置。
- [ ] `screen_info` 状态能更新画面尺寸并标记连接 ready。

## 日志与性能

- [ ] 正常远控期间没有高频逐帧日志刷屏。
- [ ] 长时间会话无明显内存增长。
- [ ] 断开后 Android VPN / capture / accessibility 相关原生资源按预期释放。
