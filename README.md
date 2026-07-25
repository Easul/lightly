# Lightly

[English](README.en.md)

一款以 Flutter 构建的 Android 浏览器与设备工具箱，集成了**远程控制**能力，同时支持 VLESS 代理、EasyTier P2P VPN、视频播放、本地文件服务、文件简易管理、剪贴板同步等功能。

Lightly 的目标不是堆叠复杂入口，而是把浏览、连接、传输和设备控制整理在一套轻量、清晰的界面中。

## 功能概览

### 远程控制
- **屏幕实时捕获**：通过浏览器查看设备屏幕，支持部分机型的编码分辨率自动降级以避免黑屏
- **远程触摸控制**：在网页上点击、滑动，实时操控设备
- **远控增强操作**：支持键盘输入、轨迹滑动、远端标注、点亮屏幕、临时关闭与控制端最小化
- **WebRTC 语音对讲**：支持控制端与被控端双向语音，EasyTier 连接下会优先复用远控链路的可达地址
- **剪贴板同步**：双向剪贴板共享
- **Web 控制界面**：无需安装客户端，同一局域网内浏览器即可控制

### 浏览器
- 基于 WebView 的完整浏览体验
- 标签页管理与会话恢复
- 地址栏建议与常用页面入口
- 收藏管理、页面长按操作与紧凑型“更多”工具面板
- 视频检测、悬浮播放、后台音频
- 下载管理（支持独立删除下载记录与文件）、站点数据清理与浏览历史管理
- 桌面模式与移动视口切换、Web 调试控制台
- 窄屏分页操作面板

### 网络能力
- VLESS over WebSocket / TLS / XUDP
- 本地混合代理（HTTP + SOCKS5）
- Hysteria2 / SOCKS5 代理协议支持，支持诊断日志记录
- EasyTier P2P VPN 集成，支持通过虚拟 IP 进行远程控制
- 局域网文件服务与剪贴板同步
- 文件简易管理：通过本地网页浏览文件树、编辑/保存/删除文本文件，并收藏常用路径

### 其他工具
- 原生视频播放器（支持视频缓存与测速控制、毫秒级时间覆盖）
- AI 翻译与对话工具
- Telegram 签到工具与消息文本选择
- 计算器与 2048 小工具

## 界面与交互

- 使用低饱和主题绿、浅灰背景和白色内容块，减少大面积纯黑与高饱和红色
- 设置页按浏览、网络服务和远程控制等功能分组，避免连续堆叠大卡片
- 短操作弹窗使用紧凑宫格；长操作弹窗使用纯文字列表；确认弹窗保持小尺寸和明确主次操作
- 普通状态使用主题色，危险色只用于退出、删除、断开和错误提示
- 视频画面、远程屏幕和键盘等沉浸式场景保留必要的深色背景

设计令牌、弹窗分类和组件约束见 [界面设计规范](docs/ui-design.md)。

## 安装

前往 [GitHub Releases](https://github.com/Easul/lightly/releases) 下载 APK。

推荐：
- `app-arm64-v8a-release.apk`：64 位 Android 设备
- `app-armeabi-v7a-release.apk`：32 位 Android 设备

要求：
- Android 7.0 及以上

## 快速开始

1. 安装并打开应用
2. 进入浏览器主页开始访问网站
3. **远程控制**：前往 **设置 → 远程控制** 启动服务，在同一局域网浏览器访问对应地址即可操控设备
4. 如需代理：前往 **设置 → 代理** 配置 VLESS 节点
5. 如需 P2P VPN：前往 **设置 → P2P VPN** 配置 EasyTier
6. 如需网页文件编辑：前往 **设置 → 文件简易管理** 启动服务，默认访问 `http://127.0.0.1:12580`

## 文档

### 中文
- [快速入门](docs/quickstart.md)
- [开发指南](docs/development.md)
- [架构文档](docs/architecture.md)
- [架构迁移路线](docs/architecture-roadmap.md)
- [工程维护待办](docs/maintenance-backlog.md)
- [远程控制架构](docs/remote-control-architecture.md)
- [界面设计规范](docs/ui-design.md)
- [发布构建说明](docs/release_build.md)
- [浏览器回归清单](docs/browser_regression_checklist.md)
- [远程控制回归清单](docs/remote_control_regression_checklist.md)
- [浏览器 / 远控模块地图](docs/browser_remote_module_map.md)
- [v1.0.7 功能更新摘要](docs/release-summary-v1.0.7.md)
- [v1.0.8 功能更新摘要](docs/release-summary-v1.0.8.md)
- [EasyTier 编译记录](docs/easytier-build.md)
- [EasyTier 状态共享给 Monitor](docs/easytier-state-sharing.md)

### English
- [Quick Start](docs/quickstart.en.md)
- [Development Guide](docs/development.en.md)
- [Architecture](docs/architecture.en.md)
- [Architecture Migration Roadmap](docs/architecture-roadmap.en.md)
- [Engineering Maintenance Backlog](docs/maintenance-backlog.en.md)
- [Remote Control Architecture](docs/remote-control-architecture.en.md)
- [UI Design Guidelines](docs/ui-design.en.md)
- [v1.0.7 Release Summary](docs/release-summary-v1.0.7.en.md)
- [v1.0.8 Release Summary](docs/release-summary-v1.0.8.en.md)
- [EasyTier Build Notes](docs/easytier-build.en.md)
- [Sharing EasyTier State with Monitor](docs/easytier-state-sharing.en.md)

## 技术栈

- Flutter 3.41.6
- Dart 3.11.4
- Kotlin / Android SDK
- Rust EasyTier JNI 集成
- `flutter_inappwebview`
- `sqflite` / `shared_preferences`

## 构建

开发调试：

```bash
flutter pub get
flutter run --debug
```

发布构建：

```bash
bash scripts/build_multi_abi.sh
```

发布脚本会生成 64 位与 32 位两个 APK，并使用 `5000 + main 分支提交数` 作为 Android `versionCode`，用户可见版本使用 `vX.Y.Z+<commit>`。

发布前请同时检查 [发布构建说明](docs/release_build.md) 中的 ABI、版本号、哈希和安装验证步骤。不要提交 `target/`、`jniLibs/` 下的生成产物或本地构建 APK。

## 致谢

[LinuxDO](https://linux.do/)

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。
