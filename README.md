# Lightly

[English](README.en.md)

一款 Flutter Android 浏览器，集成了**远程控制**能力，同时支持 VLESS 代理、EasyTier P2P VPN、视频播放、本地文件服务、剪贴板同步等功能。

## 功能概览

### 远程控制
- **屏幕实时捕获**：通过浏览器查看设备屏幕，支持部分机型的编码分辨率自动降级以避免黑屏
- **远程触摸控制**：在网页上点击、滑动，实时操控设备
- **WebRTC 语音对讲**：支持控制端与被控端双向语音，EasyTier 连接下会优先复用远控链路的可达地址
- **剪贴板同步**：双向剪贴板共享
- **Web 控制界面**：无需安装客户端，同一局域网内浏览器即可控制

### 浏览器
- 基于 WebView 的完整浏览体验
- 标签页管理与会话恢复
- 地址栏建议与常用页面入口
- 视频检测、悬浮播放、后台音频
- 下载管理与站点数据清理

### 网络能力
- VLESS over WebSocket / TLS / XUDP
- 本地混合代理（HTTP + SOCKS5）
- EasyTier P2P VPN 集成，支持通过虚拟 IP 进行远程控制
- 局域网文件服务与剪贴板同步

### 其他工具
- 原生视频播放器
- 计算器与 2048 小工具

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

## 文档

### 中文
- [快速入门](docs/quickstart.md)
- [开发指南](docs/development.md)
- [架构文档](docs/architecture.md)
- [EasyTier 编译记录](docs/easytier-build.md)
- [EasyTier 状态共享给 Monitor](docs/easytier-state-sharing.md)

### English
- [Quick Start](docs/quickstart.en.md)
- [Development Guide](docs/development.en.md)
- [Architecture](docs/architecture.en.md)
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

## 致谢

[LinuxDO](https://linux.do/)

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。
