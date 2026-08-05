# Lightly

[English](README.en.md)

Lightly 是一款面向 Android 的浏览器与设备工具箱，把网页浏览、代理与 P2P 网络、文件传输、
媒体播放和远程控制放在同一套轻量界面中。应用以 Flutter 构建，网络核心和 Android 平台能力由
Rust/Kotlin 提供；Telegram、WebRTC 语音与 EasyTier 原生运行时按需安装，不重复打包 Flutter。

当前发布重点见 [v1.0.11 完整更新说明](docs/release-summary-v1.0.11.md)。

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
- 视频检测、YouTube 原生解析、悬浮播放、后台音频
- 可恢复下载：保留登录态请求上下文、跨重定向安全控制、断点续传、可靠文件名解析
- 下载记录与文件独立管理，支持按站点清理 Cookie、WebStorage、IndexedDB 和 Service Worker
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

### 可选插件
- Telegram、WebRTC 语音和 EasyTier 以同签名纯 Android companion APK 提供，宿主 APK 不再重复携带这些原生运行时
- Lightly 内置与当前宿主版本匹配的插件 URL、ABI、大小和 SHA-256，不在运行时信任远程 manifest
- 插件下载支持 Lightly 代理、GitHub 直连、持续低速/超时后镜像回退，以及用户自定义 HTTPS 镜像前缀
- GitHub Actions 使用同一 Release keystore 构建 Lightly 与六个 ABI 插件包，并在发布前交叉验证签名

## v1.0.11 重点变化

- 新增音乐播放器：手动配置音乐 API、在线搜索与分组播放、通知栏控制、下载到本地库并保留封面/歌词/元数据。
- 修复 YouTube 长视频解析只得到约半小时内容的问题：分段媒体捕获归一化为完整时长候选，并复用已解析的 watch 页面结果。
- Google 验证页只在 watch 主导航判定，解析轮询可跨页内导航，减少 20 秒预算超时与重复解析失败。
- 浮动视频播放器支持左右双击 ±5 秒、横向拖动预览进度、长按 3 倍速，小窗模式只保留关闭按钮。
- 视频时长超过 1 小时时正确显示小时位。
- Release 继续固定并校验新版 yt-resolver AAR；未变化的 Telegram/WebRTC/EasyTier companion 复用已发布 manifest。

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
- [GitHub Release 与插件交付](docs/github-release-delivery.md)
- [可选插件发布说明](docs/optional-plugin-release.md)
- [插件交付与 YouTube 二进制发布改造说明](docs/release-summary-plugin-delivery.md)
- [浏览器回归清单](docs/browser_regression_checklist.md)
- [远程控制回归清单](docs/remote_control_regression_checklist.md)
- [浏览器 / 远控模块地图](docs/browser_remote_module_map.md)
- [v1.0.7 功能更新摘要](docs/release-summary-v1.0.7.md)
- [v1.0.8 功能更新摘要](docs/release-summary-v1.0.8.md)
- [v1.0.10 完整更新说明](docs/release-summary-v1.0.10.md)
- [v1.0.11 完整更新说明](docs/release-summary-v1.0.11.md)
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
- [v1.0.10 Release Summary](docs/release-summary-v1.0.10.en.md)
- [v1.0.11 Release Summary](docs/release-summary-v1.0.11.en.md)
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
