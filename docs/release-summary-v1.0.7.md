# v1.0.7 功能更新摘要

本文记录当前功能分支合并到 `main` 时带入的主要能力，便于发布说明、回归测试和后续维护对照。

## 新增能力

- **文件简易管理**：设置页新增 `文件简易管理`，默认目录 `/storage/emulated/0`、默认端口 `12580`，提供网页文件树、常见文本文件编辑保存、文件删除确认、收藏路径和手机/电脑响应式 UI。
- **远程控制增强**：控制端支持最小化悬浮点、临时关闭、点亮屏幕、单向/轨迹滑动切换、键盘输入面板和远端标注圈。
- **P2P / EasyTier no-VPN 模式**：P2P 设置支持 no-tun/no-VPN 启动，远控可复用已有 no-VPN EasyTier 实例，并通过 no-tun SOCKS5 portal 连接 `10.126.*` 目标。
- **EasyTier 状态共享**：通过签名权限保护的 ContentProvider 暴露 EasyTier 运行状态，便于同签名 Monitor 应用复用 Lightly 的 P2P VPN 状态。
- **解析器视频标题**：原生视频解析结果支持 `title`，用于弹窗标题与下载文件名。
- **代理节点管理**：代理设置支持保存、选择、删除多个节点，并按协议显示对应字段。

## 可靠性与兼容性

- 红米 / Qualcomm 远控黑屏路径增加捕获尺寸降级和解码器延迟重配，减少高分辨率 AVC 失败导致的黑屏。
- 远控屏幕帧发送支持丢弃旧 delta 帧、优先保留新帧，降低弱网下的延迟堆积。
- 远控连接区分端口探测与真实会话，避免仅扫描端口就触发“对方已断开”。
- EasyTier no-tun SOCKS 配置顺序、端口映射与关闭生命周期进一步收敛，避免端口冲突、实例重启和 VPN 图标残留。
- 浏览器 overlay、tab 切换、WebView keep-alive、下载播放、页面查找和外部文件打开路径做了稳定性修复。
- 本地 SOCKS5 / Telegram 兼容性修复包括认证协商、CONNECT bind 回复和半关闭错误分类。

## 结构重构

- Browser / Remote / EasyTier / Downloads / Proxy 多个大页面与 widget 拆分为 action、section、helper、coordinator 文件，降低单文件复杂度。
- 浏览器备份服务拆分为模型、文件写入和 Web 数据收集组件。
- 悬浮视频控制、收藏页弹窗、远控 setup/session 组件、EasyTier 设置动作等 UI 组件独立化。

## 发布与验证

- `scripts/build_multi_abi.sh` 是多 ABI 发布构建的统一入口，生成 `app-arm64-v8a-release.apk` 与 `app-armeabi-v7a-release.apk`。
- GitHub Actions release 工作流也调用同一构建脚本，保持本地和 CI 的 `TARGET_ABI`、混淆、split-debug-info 与版本规则一致。
- Android `versionCode` 继续使用 `5000 + main 分支提交数`，用户可见版本为 `vX.Y.Z+<6位提交号>`。

## 建议回归重点

1. `设置 → 文件简易管理`：启动服务、浏览目录、编辑保存文本文件、删除确认、收藏滚动、局域网访问。
2. 远控 LAN 与 EasyTier `10.126.*`：屏幕、触摸、键盘、轨迹滑动、标注、临时关闭、最小化、关闭清理。
3. Redmi / Qualcomm 设备：被控端首帧出现、控制端高分辨率解码不黑屏。
4. P2P no-VPN：不弹系统 VPN 权限、不显示 VPN 图标、已有 P2P no-tun 实例可被远控复用。
5. 浏览器：tab/overlay 动画、下载页播放、外部文件打开、X/YouTube 移动布局、站点数据清理和备份恢复。
