# Lightly、可选插件与私有 AAR 的 GitHub Release 发布链路

## 目标

一次 `v*` tag 发布同时产出：

- Lightly 的 `arm64-v8a` 与 `armeabi-v7a` APK。
- Telegram、WebRTC、EasyTier 各两个 ABI 的纯 Android companion APK。
- 与本次 Lightly 精确匹配的 `plugins.json`。
- 构建时下载并嵌入的已混淆 YouTube resolver AAR。

插件运行时不下载远程 manifest。CI 生成的 `plugins.json` 会在最终 Lightly 构建前复制到
`assets/optional_plugins/plugins.json`，因此版本、URL、大小和 SHA-256 都受 Lightly APK 签名保护。
镜像只能代理固定 URL 对应的字节，不能替换 Lightly 选择的插件版本或哈希。

## 仓库职责

| 仓库 | 内容 | 是否包含源码 |
|---|---|---|
| `Easul/lightly` | Lightly、三个 companion 源码、Actions 和构建脚本 | 是 |
| `Easul/lightly-plugins` | 六个 companion APK 与 `plugins.json` Release assets | 否，仅发布产物 |
| YouTube resolver 二进制仓库 | R8 后的 AAR 与 `SHA256SUMS` Release assets | 可以只发布二进制 |

YouTube 二进制仓库公开时，任何人仍能从 AAR 或最终 Lightly APK 中提取并反编译代码。R8 只能降低
可读性，不能提供密码学意义上的源码保密。不要把 API key、签名私钥或其他秘密写入 AAR。

## 运行时下载顺序

设置页的“插件下载”提供三个模式：

1. `自动`：代理已启用且可启动时先通过代理访问 GitHub，否则直连 GitHub；连接超过 12 秒、连续
   10 秒无数据、HTTP/重定向失败，或下载 8 秒后平均速度低于 48 KiB/s 时，删除临时文件并直连镜像。
2. `GitHub`：只请求原始 GitHub URL；代理可用时使用代理，否则直连，不回退镜像。
3. `镜像`：只直连用户配置的镜像前缀。

默认镜像前缀为 `https://ghfast.top/`。例如：

```text
https://ghfast.top/https://github.com/Easul/lightly-plugins/releases/download/plugins-v1/plugin.apk
```

不查询大陆 IP。IP 定位会引入额外网络依赖、隐私披露和误判；实际 GitHub 请求结果更可靠。

## 下载信任链

每次安装必须依次通过：

1. 从已签名 Lightly APK 内读取 `plugins.json`。
2. 只接受 HTTPS GitHub URL；自定义镜像也必须是 HTTPS。
3. 限制重定向次数与响应大小。
4. 文件大小等于 manifest 的 `size`。
5. 文件 SHA-256 等于 manifest 的 `sha256`。
6. Android 验证 APK 包名。
7. Android 验证 APK 与当前 Lightly 使用同一签名证书。
8. 运行时绑定前再次检查包签名、启用状态、feature ID 与 API version。

即使镜像返回另一份 APK，也无法同时通过固定哈希与同签名校验。

## GitHub 配置

在 `Easul/lightly` 的 `Settings -> Secrets and variables -> Actions` 配置：

### Repository variables

| 名称 | 示例 | 用途 |
|---|---|---|
| `PLUGIN_RELEASE_REPOSITORY` | `Easul/lightly-plugins` | companion Release 目标仓库 |
| `YOUTUBE_RESOLVER_AAR_URL` | `<private-https-release-asset-url>` | 固定 YouTube AAR 下载地址 |
| `YOUTUBE_RESOLVER_AAR_SHA256` | `<64-character-sha256>` | 构建前校验 AAR；必须来自同一 tag 的 `SHA256SUMS` |

### Repository secrets

| 名称 | 用途 |
|---|---|
| `KEYSTORE_BASE64` | Lightly 与 companion 共用 Release keystore |
| `KEYSTORE_PASSWORD` | keystore 密码 |
| `KEY_PASSWORD` | `upload` alias 密码 |
| `PLUGIN_RELEASE_TOKEN` | 对 `lightly-plugins` 具有 Contents: Read and write 的 fine-grained token |
| `YOUTUBE_RESOLVER_GITHUB_TOKEN` | 仅私有 AAR 仓库需要；使用对 `<private-resolver-repository>` 有 Contents: Read 权限的 fine-grained token，公开仓库留空 |

不要在 fork/PR 工作流中暴露这些 secrets，也不要使用 `pull_request_target` 执行来自 PR 的构建脚本。

## YouTube AAR 发布

resolver 源码位于独立私有仓库。提交到其 feature 分支并合并到 `main` 后，先等待主分支 CI 完成
测试、R8 和反射 API 校验，再创建新的不可变 `v*` tag。tag CI 会重新构建并发布 resolver AAR
与 `SHA256SUMS`。

本地发布前验证：

```bash
cd <private-resolver-checkout>
scripts/build_release.sh
```

脚本会在 Debug 字节码上运行单元测试，构建启用 R8 的 Release AAR，使用 `javap` 验证
`YouTubeResolverBridge.apiVersion()` 与 `resolve(...)` 反射签名，并拒绝桥接类之外仍留在
`lightly.youtube.resolver` 包下的实现类，然后生成：

- `dist/<resolver-asset>.aar`
- `dist/SHA256SUMS`

推送新 tag：

```bash
git tag -a <resolver-version-tag> -m "Release <resolver-version-tag>"
git push origin <resolver-version-tag>
```

上传后把 Release asset URL 和 `SHA256SUMS` 的值写入上面的 Actions variables。升级 AAR 时必须使用
新 tag 和新哈希；每个 tag 可以继续使用同一个 resolver asset 名，但禁止覆盖旧 tag 的
asset 后继续使用原 SHA。

resolver 可以放在私有仓库。此时 Lightly 仓库自身的 `GITHUB_TOKEN` 无权读取另一个私有仓库，
必须配置 `YOUTUBE_RESOLVER_GITHUB_TOKEN`。下载脚本识别 GitHub Release URL 后会使用
`gh release download` 获取私有 asset，再执行相同的 SHA-256 和桥接合同校验。这个 token 只供
tag/手动 Release 工作流使用，不得写入 Variables、源码或 fork/PR 构建。

companion 产物仓库与 resolver 仓库的可见性要求不同：前者由用户设备匿名下载，默认应保持公开；
后者只在受控 CI 构建时下载，因此可以私有。

## `v*` Action 执行顺序

`.github/workflows/release.yml` 按以下顺序执行：

1. 固定 Flutter 3.41.6、Java 17、Gradle 8.14 和 Rust Android targets。
2. 校验 tag/手动版本格式，计算 `5000 + main commit count` 和 plugin release tag。
3. 解码 Release keystore，构建两个 ABI 的 proxy-core。
4. 从固定 URL 下载 YouTube AAR，校验 SHA-256、桥接 API 和 R8 包边界。
5. 根据 `auto` / `build` / `reuse` 决定 companion 处理方式。
6. 需要重建时准备 TDLib，使用同一 keystore 构建六个 companion，检查 ABI、Flutter/Dart runtime
   泄漏与插件间签名，并生成 `plugins.json`；复用时下载最近发布的 manifest。
7. 校验 manifest 后嵌入 Lightly assets。
8. 构建 Lightly 两个 ABI Release APK，生成并回验 `SHA256SUMS`。
9. 重建 companion 时，将六个插件的签名与最终 Lightly APK 再次比较，并先发布
   `lightly-plugins` Release。
10. 从 `docs/releases/<tag>.md` 读取版本化说明，追加 commit、build label 和 Android
    versionCode，再创建或更新 Lightly Release。
11. 发布两个 APK 与 `SHA256SUMS`；任何预期产物缺失或校验失败都会终止发布。

### 跳过未变化的 companion

Release 工作流支持 `auto`、`build`、`reuse` 三种 optional plugin 模式：

- `auto`：比较上一个 Lightly tag；companion 源码、IPC 合同和打包脚本未变化时跳过六个 APK 构建。
- `build`：强制重建、验签并发布 companion，适用于插件变更或签名证书轮换。
- `reuse`：强制复用 `lightly-plugins` 最新 Release 的 `plugins.json`。

手动运行工作流时通过 `optional_plugins` 选择；tag 自动发布可用 Repository Variable
`OPTIONAL_PLUGIN_BUILD_MODE` 覆盖，未配置时默认为 `auto`。复用模式通过 `PLUGIN_RELEASE_TOKEN`
从 companion 仓库下载、校验并嵌入 manifest，因此新 Lightly APK 内继续保存插件 URL、大小和
SHA-256；只是不重复编译和发布未变化的 companion。
签名证书变化时不得复用旧插件，必须选择 `build`。

`workflow_dispatch` 只构建 Actions artifacts；推送 `v*` tag 才创建 GitHub Releases。

## 本地验证

```bash
flutter test test/optional_plugins/
flutter analyze
bash -n scripts/build_optional_plugins.sh \
  scripts/embed_optional_plugin_manifest.sh \
  scripts/fetch_youtube_aar.sh \
  scripts/package_youtube_aar_release.sh \
  scripts/verify_optional_plugin_bundle.sh
```

完整本地链路：

```bash
extensions/telegram/scripts/prepare_tdlib.sh
scripts/build_optional_plugins.sh
scripts/embed_optional_plugin_manifest.sh
scripts/build_multi_abi.sh
scripts/verify_optional_plugin_bundle.sh
```

发布后至少验证自动模式的代理 GitHub、无代理 GitHub、故障镜像回退，以及手动 GitHub/镜像模式。
