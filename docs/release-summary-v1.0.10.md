# v1.0.10 完整更新说明

本文汇总 `v1.0.8` 之后进入 Lightly 的功能、兼容性修复、性能优化、架构迁移和发布流程变化。
`v1.0.9` 是这一批改动的中间发布点；重新发布的 `v1.0.10` 包含下述完整结果，以及更新后的
私有 YouTube resolver 二进制依赖。

## 一、用户可见变化

### 1. 可选原生插件

Telegram、WebRTC 语音和 EasyTier 已从宿主 APK 的运行时中拆出，改为同签名的纯 Android
companion APK：

- 每项能力分别提供 `arm64-v8a` 与 `armeabi-v7a` 包，共六个插件 APK。
- companion 不包含 FlutterEngine、Dart AOT、`libflutter.so` 或第二套业务 UI。
- Lightly 继续拥有设置、配置、备份、下载提示与功能入口；插件只拥有原生会话和 JNI 资源。
- 插件缺失或版本不兼容时，Lightly 会引导安装/升级，不阻塞浏览器和其他不依赖插件的功能。
- 已安装且 API 兼容的插件不会仅因 Lightly 升级而被强制替换。

设置中的插件下载支持自动、仅 GitHub 和仅镜像模式。自动模式会优先使用当前 Lightly 代理或
GitHub 直连，在连接失败、空闲超时或持续低速时切换到 HTTPS 镜像。镜像只改变传输路径，最终包
仍必须通过内置 URL、精确大小、SHA-256、包名和同签名校验。

### 2. YouTube 原生解析与播放

Lightly 新增私有纯 Android YouTube resolver AAR，通过稳定的
`YouTubeResolverBridge` API 1 反射合同接入：

- YouTube 地址先在正常浏览器标签中打开，用户点击页内播放按钮后才开始解析。
- 解析前暂停当前可见 WebView 的媒体，避免浏览器播放器与短生命周期 resolver WebView 争抢音频和解码器。
- resolver 复用 WebView 登录态，让 YouTube 当前 MWEB player 发出 muxed itag 18 请求，再捕获最终
  `video/mp4` GoogleVideo 地址，不在 Lightly 内维护 `base.js` 签名算法。
- 返回的视频标题会显示在解析结果中并作为下载初始文件名。
- Cookie、User-Agent、Referer 和完整媒体 URL 仅进入内存中的本地视频代理/下载上下文，不写入日志。

本次重新发布固定了新版本 resolver AAR 及其 SHA-256。该版本等待播放器元素真正就绪，覆盖完整
解析预算，使用实际 WebView User-Agent 与移动视口，处理渲染进程退出，并等待 CDN 重定向候选
稳定后再返回地址。

### 3. 下载可靠性

WebView 发起的下载现在保留必要且受控的请求上下文：

- 从 CookieManager 读取目标站点 Cookie，转发下载回调中的 User-Agent。
- Referer 会移除用户信息、query 和 fragment 后再发送。
- 显式处理有限次数的 HTTP(S) 重定向；跨 origin 时移除 Cookie、Authorization、
  Proxy-Authorization 和 Referer。
- 对连接、TLS、响应头等待、流空闲、HTTP 408/429/5xx 等瞬态失败执行有上限的退避重试。
- 使用 Range 和 identity encoding 从磁盘实际文件长度续传；校验 `Content-Range` 起点，并使用
  ETag/Last-Modified 的 `If-Range` 防止文件版本错配。
- 服务器忽略 Range 并返回 200 时会截断重来，不会把完整响应追加到部分文件后面。
- 普通失败保留部分文件和失败记录，可从下载页重试；只有明确选择“记录及文件”才删除文件。
- 同一下载记录/路径不会被两个活动任务同时写入。

文件名解析也得到补强：优先使用 `Content-Disposition`（含 RFC 5987 `filename*`），其次使用
文件名型 query、最终重定向 URL 和 MIME；用户手动修改过的文件名不会被响应覆盖。若 `.apk` 等
非 HTML 文件最终返回登录页/分享页 HTML，会明确报错而不是把页面保存成伪二进制文件。

### 4. 站点数据与下载记录

- 下载记录持久化，应用重启后仍能查看完成、失败和部分下载状态。
- 单项下载可选择只删记录或同时删除文件；全局清理下载记录不会误删已下载文件。
- 当前站点数据清理按 Cookie 的真实 domain/path 删除，并结合已记录 origin 清理 WebStorage、
  IndexedDB、Cache API 和 Service Worker。
- 站点清理不会调用全局 WebView 缓存清理，也不会影响其他站点。

### 5. 浏览器交互性能

标签页切换器和底部弹层打开/关闭期间，非关键 BrowserPage 刷新会延后合并。WebView 的
keepAlive、加载状态和悬浮层指针冻结继续由独立状态管理，避免弹层动画与平台 WebView 重建竞争。
标签列表保持固定布局成本，操作在弹层退场后执行，减少白屏、旧标签残影和明显掉帧。

## 二、网络与媒体正确性

### 1. 代理绕过边界

代理绕过规则从字符串包含/后缀误判改为主机边界匹配：只接受 host 与规则完全相同，或以
`.规则域名` 结尾。`googlevideo.com` 因而不会再错误命中 `google.com` 绕过项，修复 YouTube
播放请求被意外 DIRECT 路由后出现的 403。

### 2. 受限媒体请求头

解析得到的敏感 headers 只允许流向随机 token 保护的本地 VideoProxyServer 上下文：

- token 与精确目标 URL 绑定，并在代理停止时清理。
- 只接受 GET/HEAD、HTTP(S) 和受控 GoogleVideo host 边界。
- 本地客户端不能自行提交 Cookie/Authorization，也不能要求代理跟随任意上游重定向。
- 日志不记录 Cookie、完整 GoogleVideo URL 或签名参数。

## 三、Telegram companion

Telegram TDLib 已从 Lightly 宿主移入 `lightly.tool.plugin.telegram`：

- Lightly 保留 TG 工具 UI、App ID/App Hash/手机号、签到目标与命令以及统一备份所有权。
- companion 拥有自己的 TDLib 数据库和登录会话；普通同签名升级保留会话，首次迁移、卸载或清数据
  需要重新登录 Telegram。
- 宿主不再携带 `libtdjson.so`，也不再为了 Dart model 引入 Flutter TDLib 包。
- TDLib 参数设置后立即应用本地 SOCKS5；运行中的本地代理启动、停止或换端口时会重新配置。
- receive loop 保持单线程，重绑前等待旧 receive 返回，避免 TDLib 原生 abort。
- 初始 authorization update 不会在宿主取得 client ID 前启动 receiver 而被丢弃。
- companion 自行声明 INTERNET，并在 MIUI 上通过受签名权限保护的透明 Activity 启动
  `dataSync` 前台服务，再由 Lightly 绑定。
- 最后一个宿主绑定或 callback Binder 丢失时，前台服务与 TDLib runtime 一并清理。

日志热路径也做了收敛：普通 TDLib update 不再为了日志反复解析完整 JSON，敏感配置和消息正文仍不
写入运行日志。

## 四、WebRTC 语音 companion

WebRTC voice runtime 被迁移到 `lightly.tool.plugin.webrtc`：

- companion 拥有 PeerConnectionFactory、麦克风、扬声器、track 和 Android AudioManager 路由。
- Lightly 保留控制 TCP 信令、EasyTier overlay candidate 改写和会话可用性策略。
- 录音权限 Activity 在前台启动 microphone 类型 foreground service 后才打开麦克风，兼容
  Android 14+ 和 MIUI 对后台麦克风的限制。
- 补齐 ACCESS_NETWORK_STATE，避免 WebRTC NetworkMonitor 跨 JNI 抛出 SecurityException。
- 有线、USB、Bluetooth SCO、BLE headset 和 hearing-aid 路由可随热插拔更新。
- Android 12+ 优先使用 communication device；MIUI 枚举延迟时保留受控 SCO fallback。
- 语音准备或权限的瞬态失败不会永久隐藏麦克风按钮，用户可以再次触发准备流程。

## 五、EasyTier companion

EasyTier JNI/FFI、native instance、网络监控、TUN fd 和 VpnService 已迁移到
`lightly.tool.plugin.easytier`。Lightly 继续拥有 profile、备份、P2P/远控 UI 和 no-tun 策略。

- AIDL 与同签名校验保护跨包调用。
- VPN 授权仍由最小透明 Activity 完成，不引入插件业务 UI。
- 网络信息在 companion 专用监控线程采集并缓存，Binder/UI 查询读取最新 snapshot，减少重复 JNI
  collect 和主线程 JSON 处理。
- 宿主失联时关闭 companion 持有的 native runtime 与前台资源。

## 六、远程控制与热路径优化

- RemoteControlService 继续作为控制、屏幕 socket 与会话状态的唯一 owner，页面只通过 presentation
  runtime/coordinator 提交意图。
- 视频帧使用原始 `Uint8List` 经过 typed gateway，不增加 JSON/base64 或不必要的 buffer copy。
- 性能统计只保留有界采样，避免每帧创建 DateTime、日志和统计对象。
- H.264 解析、屏幕捕获、页面 widget、连接策略、语音协调和平台 gateway 迁移到明确的 feature
  层级，行为与现有远控协议保持兼容。

## 七、架构迁移

`v1.0.8` 之后完成了一轮大规模但按小提交推进的模块边界整理：

- 新增 `lib/app/` composition root，集中创建 `AppServices`、路由和跨 feature coordinator。
- `AppRuntimeCoordinator` 负责冷启动服务策略；`BrowserRuntimeCoordinator` 管理 proxy、本地 HTTP 和
  clipboard 等浏览器相关 runtime，不再依赖 BrowserPage 保持 mounted。
- Android raw MethodChannel 从页面/业务代码收敛到 typed platform gateways 与独立 Kotlin handlers。
- AI、Telegram、Calculator、2048、Local Sharing、Proxy、EasyTier、Remote Control、Video 按
  presentation/application/domain/infrastructure 的实际复杂度迁移到 feature 目录。
- AppDatabase 成为共享 SQLite schema 的唯一 owner；新增数据所有权、敏感性、备份和删除语义文档。
- Video 只保留 FloatingVideoPlayerCoordinator 这一活动播放 owner，删除不可达的旧全页播放器和重复
  resolver 路径。

这一轮迁移以行为保持为原则；代理绕过边界修复、插件抽离和 YouTube 接入等行为变化均使用独立提交。

## 八、GitHub Release 与供应链

发布链路现在明确区分三类产物：

1. Lightly 两个 ABI APK。
2. `lightly-plugins` 中六个 companion APK 与 `plugins.json`。
3. 私有 resolver Release 中的 R8 AAR 与 `SHA256SUMS`。

主要调整：

- YouTube AAR 从固定 HTTPS Release URL 获取，并在任何 Gradle 构建前校验固定 SHA-256。
- 私有仓库下载使用 Contents: Read 的 fine-grained token，不把 token 写入变量、源码或日志。
- companion 使用 Gradle 8.14 与同一 Lightly keystore 构建，验证单 ABI、无 Flutter/Dart runtime、
  包名/API 和签名证书。
- `plugins.json` 在最终 Lightly 构建前嵌入 assets，运行时不信任可变化的 latest manifest。
- companion 未变化时可复用最近发布的已签名 manifest；插件合同/源码变化或签名轮换时强制重建。
- 修复 detached tag 构建、不同 `apksigner` 输出格式和 CI 缺少 companion Gradle wrapper 的问题。
- Release 同时发布两个 APK 的 `SHA256SUMS`，并从 `docs/releases/<tag>.md` 读取版本化说明。

## 九、升级说明

- 选择与设备 ABI 一致的 Lightly APK；大多数设备使用 `arm64-v8a`。
- Telegram、WebRTC 与 EasyTier 在第一次使用时可能提示安装 companion。
- 从旧的宿主内 TDLib 迁移到 Telegram companion 时需要重新登录一次；以后同签名升级保留会话。
- WebRTC 麦克风、Nearby devices、录屏、无障碍和 VPN 权限仍由相应功能按需请求。
- YouTube 原生解析需要先在 Lightly 浏览器中登录 YouTube，并从已打开的 watch 页面点击播放按钮。

## 十、验证范围

本轮提交新增或扩展了 architecture contracts、platform gateways、optional plugin manifest/download、
Telegram codec/runtime、proxy configuration、video proxy、YouTube gateway、下载、站点数据、远控视频和
WebRTC plugin 等测试。发布 CI 还会执行 AAR API/R8 校验、插件 ABI/runtime 检查、宿主/插件签名对比
和最终 APK 构建。

更细的运维与安全约束见：

- [GitHub Release 与插件交付](github-release-delivery.md)
- [可选插件发布说明](optional-plugin-release.md)
- [插件交付与 YouTube 二进制改造](release-summary-plugin-delivery.md)
- [架构文档](architecture.md)
- [远程控制架构](remote-control-architecture.md)
