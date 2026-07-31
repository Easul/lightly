# 插件交付与 YouTube 二进制发布改造说明

## 背景

可选插件已经从 Lightly 主 APK 中拆成 Telegram、WebRTC、EasyTier 三个纯 Android companion，
但此前的下载流程仍有三个缺口：运行时依赖 GitHub latest manifest、没有无代理环境的自动回退、
Lightly 与插件尚未在一个 Actions 发布事务中构建。私有 YouTube resolver 也只有本机构建入口，没有
可供公开 CI 安全消费的版本化二进制流程。

本次改造不改变三个 companion 的 AIDL 和运行时 owner，只调整发布、选择版本、下载和构建输入。

## 用户可见变化

- 设置首页新增“插件下载”。
- 可以选择自动、仅 GitHub、仅镜像。
- 可以输入自定义 HTTPS GitHub 镜像前缀。
- 可以执行真实线路测试，显示最终成功线路和首包耗时。
- 页面展示当前 Lightly APK 内固定的三个插件版本与 API version。
- 未配置代理也可以安装插件；自动模式会先直连 GitHub，再在故障或持续低速时回退镜像。

## 版本选择变化

旧流程先访问 `releases/latest/download/plugins.json`，远端 latest 可以在 Lightly 不升级时改变插件
选择。新流程把 CI 生成的 manifest 作为 Flutter asset 嵌入 Lightly：

```text
Lightly tag
  -> build companion APKs
  -> compute size / SHA-256 / release URL
  -> generate plugins.json
  -> embed plugins.json
  -> build and sign Lightly
```

因此每个 Lightly APK 都有可审计、可重现的插件集合。插件有不兼容 API 变化时，必须发布新的
Lightly；接口不变时，已安装且兼容的旧插件继续可用，不会仅因远端 latest 变化被强制重新安装。

## 下载状态机

自动模式生成两个候选 attempt：

```text
GitHub via Lightly proxy (when available)
  or GitHub DIRECT
        |
        | retryable connection / HTTP / idle / sustained-slow failure
        v
HTTPS mirror DIRECT
```

每个 attempt 使用独立 `HttpClient`。切换前会关闭旧 client、删除部分 APK、把进度重置为 0，再从
镜像完整下载；不会把两条线路的数据拼到同一个文件。

以下错误允许自动回退：连接超时、无首包/长时间无数据、非 200、重定向错误、声明长度不匹配、
下载中断，以及达到观察窗口后的持续低速。超过 manifest 大小或最终 SHA-256 不匹配属于安全错误，
不会通过换镜像掩盖。

## 安全边界

- Manifest 来自已签名 Lightly APK，不来自镜像。
- 原始 artifact URL 必须是 HTTPS GitHub URL。
- 自定义镜像前缀必须是 HTTPS，且只改变下载传输地址。
- 下载后校验精确大小和 SHA-256。
- 安装前原生层校验包名与 Lightly 同签名。
- 绑定前继续校验 feature ID、API、启用状态和签名。
- 临时 APK 只能位于 Lightly cache 下的 `optional_plugins` 目录。

## 持久化

新增 `optional_plugin_download_settings_v1`，只保存下载模式和公开镜像前缀。它不保存代理凭据、插件
登录会话或安装状态，不进入统一备份。JSON 损坏时回退自动模式与默认镜像。

## GitHub Actions

Release job 现在生成两组 artifacts：Lightly APK 与 optional plugin APK/manifest。构建 job 在最终
Lightly 构建前准备 YouTube AAR、TDLib 和插件 manifest，最终再比较六个插件与 Lightly 的签名。

发布 job 先通过 fine-grained token 写入 `lightly-plugins`；只有这一步成功，才创建当前仓库的
Lightly Release。这样用户不会下载到引用不存在插件 assets 的宿主版本。

## YouTube AAR

私有 library Release build 启用 R8，只保留 `YouTubeResolverBridge.apiVersion()` 和
`YouTubeResolverBridge.resolve(...)` 的稳定反射合同。构建后脚本解包 `classes.jar` 并通过
`javap` 检查两个公开方法：桥接合同缺失，或桥接类之外仍有实现类留在原包名下，都会失败。

`package_youtube_aar_release.sh` 默认生成 resolver AAR 与 `SHA256SUMS`，版本由私有 GitHub Release
tag 管理。公开 Actions 不需要 resolver 源码，只读取 `YOUTUBE_RESOLVER_AAR_URL` 指向的固定资产，
并在 Gradle 运行前验证 `YOUTUBE_RESOLVER_AAR_SHA256`；私有资产通过只读 token 获取。

## 测试覆盖

- 下载设置 JSON 与 SharedPreferences 往返。
- HTTPS 镜像前缀规范化和非法值拒绝。
- 有/无代理自动 attempt 顺序。
- GitHub-only 与 mirror-only 单线路行为。
- 持续低速观察窗口。
- 主线路返回可重试错误后，真实 HTTP 流切换到镜像并完成 SHA-256 校验。
- HTTP 错误响应正文停滞时按空闲超时切换线路，不会无限等待 drain。
- SHA-256 不匹配不会切换镜像，并会删除失败的临时 APK。
- Bundled manifest 解析和 ABI artifact 选择。
- YouTube Debug parser 单测、Release R8、桥接类存在与内部类名消失检查。

完整操作、Secrets 和 Variables 见
[GitHub Release 与插件交付](github-release-delivery.md)。
