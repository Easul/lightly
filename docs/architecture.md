# Lightly 架构文档

[English](architecture.en.md)

## 总览

Lightly 是一个以 Flutter 为主、结合 Kotlin 原生模块与 EasyTier Rust 组件的 Android 浏览器应用。

整体可以分成三层：

```text
UI 层（Flutter 页面与组件）
    ↓
业务层（浏览器、代理、远程控制、文件服务、视频服务）
    ↓
平台层（Android Kotlin、JNI、Rust EasyTier、MediaCodec）
```

## UI 层

主要位于 `lib/pages/` 与 `lib/widgets/`：

- `BrowserPage`：浏览器主页面
- `SettingsPage`：设置入口与功能开关
- `ClipboardPage`：剪贴板页
- EasyTier / 视频 / 数据管理 / 文件简易管理等专用页面

界面统一由 `lib/theme/app_theme.dart` 提供颜色、文字、按钮、输入框、列表、对话框与 BottomSheet 主题。设置首页使用按功能域拆分的白色分组块；短操作菜单使用紧凑宫格，长操作菜单使用纯文字列表。共享设置行位于 `lib/widgets/shared/setting_tile.dart`。

完整约束见 [界面设计规范](ui-design.md)。UI 重构不得改变 WebView keepAlive、代理连接、远控 socket 或后台服务生命周期。

## 业务层

主要位于 `lib/browser/`、`lib/services/`：

### 浏览器
- WebView 承载页面
- 标签页管理与恢复
- 地址栏建议、收藏、下载协调

### 代理
- `vless_client.dart`：VLESS 协议实现
- `local_mixed_proxy_server.dart`：本地 HTTP + SOCKS5 混合代理
- `proxy_service.dart`：代理生命周期与配置管理

### 远程控制
- 屏幕采集与 H.264 帧管线，Android 端负责 MediaProjection / MediaCodec 编码，Flutter 端负责 socket 传输与解码显示
- 触摸、键盘、全局动作、点亮屏幕、轨迹滑动与标注注入
- WebRTC 双向语音，EasyTier 场景下优先使用远控 TCP 已验证的远端地址
- 剪贴板与状态消息联动

### 本地服务
- HTTP 文件服务
- 文件简易管理服务：本地网页文件树、文本编辑保存、删除确认和收藏路径
- 剪贴板 HTTP 服务

### EasyTier / P2P
- VPN 与 no-tun/no-VPN 两种运行模式
- no-VPN 远控通过 EasyTier no-tun SOCKS5 portal 访问虚拟 IP
- 签名权限保护的 EasyTier 状态 Provider，供同签名 Monitor 应用读取运行状态

## 平台层

位于 `android/app/src/main/kotlin/` 与 `jniLibs/`：

- `MainActivity.kt`：Flutter 与原生能力桥接
- `ScreenCapture.kt`：屏幕捕获与 AVC 编码，包含机型兼容的编码尺寸 fallback
- `H264Decoder.kt`：视频解码
- `RemoteControlAccessibilityService.kt`：远控输入、全局动作、标注与断连提示
- `EasyTierInfoProvider.kt` / `EasyTierStateStore.kt`：EasyTier 状态共享
- EasyTier JNI / Rust `.so`：P2P VPN 核心能力

## 关键数据流

### 浏览器代理链路

```text
Browser WebView
  → LocalMixedProxyServer
  → VlessClient
  → Remote VLESS server
  → response back to WebView
```

### EasyTier VPN 链路

```text
Flutter UI
  → MethodChannel
  → Kotlin wrapper
  → EasyTier JNI
  → Rust easytier core
  → Android VpnService / tun
```

### 远程控制链路

```text
LAN browser
  → Remote control HTTP interface
  → Android capture / input services
  → screen / touch / clipboard / audio
```

远控模块按职责拆分为连接流程、消息路由、屏幕帧管线、健康检测、语音协调等组件，详见 [Browser / Remote 模块分类图](browser_remote_module_map.md)。

### 文件简易管理链路

```text
Settings → SimpleFileManagerService
  → Dart HttpServer (default 12580)
  → Web file tree / editor
  → safe read / save / delete under configured root
```

## 性能注意点

- 浏览进度更新使用节流，避免高频重建
- WebSocket / 代理热路径避免逐包详细日志
- 浏览器滚动位置与视频检测使用阈值 / 防抖
- WebView、服务、流对象需要及时释放

## 相关文档

- [快速入门](quickstart.md)
- [开发指南](development.md)
- [界面设计规范](ui-design.md)
- [浏览器 / 远控模块地图](browser_remote_module_map.md)
- [浏览器回归清单](browser_regression_checklist.md)
- [远程控制回归清单](remote_control_regression_checklist.md)
- [v1.0.7 功能更新摘要](release-summary-v1.0.7.md)
- [v1.0.8 功能更新摘要](release-summary-v1.0.8.md)
