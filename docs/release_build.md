# Release 构建清单

本项目发布 Android APK 时优先使用多 ABI 分包。不要只依赖 `flutter build apk --split-per-abi`，因为仓库内存在手动 `jniLibs/`，需要 `TARGET_ABI` 参与过滤。

## 构建前

- [ ] 工作区已提交，`git status --short` 为空。
- [ ] 确认当前 commit 是要发布的源码版本。
- [ ] 相关自动测试通过。
- [ ] 如触碰 Browser / Remote / Proxy / EasyTier，完成对应回归清单。
- [ ] 如触碰文件简易管理，验证启动服务、文件树、编辑保存、删除确认、收藏路径和局域网访问。
- [ ] 确认没有把 `rust/proxy-core/target/**` 或临时构建产物加入提交。

## 推荐命令

```bash
bash scripts/build_multi_abi.sh
```

脚本负责：

- 清理旧 APK 输出。
- 设置 `TARGET_ABI`。
- 使用 `--release --obfuscate --split-debug-info=build/app/outputs/symbols`。
- 分别构建：
  - `app-arm64-v8a-release.apk`
  - `app-armeabi-v7a-release.apk`
- 使用 `BUILD_VERSION_LABEL` 注入 `v<latest-tag>+<6-digit commit id>` 形式的用户可见版本标签。
- 使用 `BUILD_VERSION_CODE` 注入 `5000 + main 分支提交数` 形式的 Android `versionCode`。

GitHub Actions 的 `.github/workflows/release.yml` 也调用该脚本；更新发布流程时应优先修改脚本，再让 CI 复用脚本行为，避免本地与 CI 的 ABI 过滤、混淆或版本规则漂移。

## GitHub Actions 联合发布

`v*` tag 不再只构建 Lightly。工作流会先获取固定 URL/SHA-256 的 R8 YouTube AAR，再构建 Telegram、
WebRTC、EasyTier 的 32/64 位 companion，生成并嵌入 `plugins.json`，最后构建 Lightly。所有 companion
与最终 Lightly 必须使用同一证书。

发布顺序固定为先 `lightly-plugins`、后 Lightly；插件仓库发布失败时不得公开引用缺失 assets 的
Lightly Release。所需 Variables、Secrets 和完整执行顺序见
[GitHub Release 与插件交付](github-release-delivery.md)。

## 产物检查

- [ ] `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` 存在。
- [ ] `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` 存在。
- [ ] 64 位包只包含 `arm64-v8a` 相关 native slice。
- [ ] 32 位包只包含 `armeabi-v7a` 相关 native slice。
- [ ] `build/app/outputs/symbols/` 存在并与本次构建对应。
- [ ] APK 内 `assets/optional_plugins/plugins.json` 与 `build/optional-plugins/plugins.json` 一致。
- [ ] 六个 companion APK 均存在、只有目标 ABI、没有 Flutter/Dart runtime。
- [ ] `scripts/verify_optional_plugin_bundle.sh` 已确认 companion 与 Lightly 证书一致。
- [ ] YouTube AAR SHA-256 与 Actions variable 一致，APK 内存在 `YouTubeResolverBridge`。

## 版本规则

- 用户可见版本标签使用 `vX.Y.Z+<commit>`。
- 不要在 UI 上额外再拼一个 `v`。
- Android `versionCode` 默认使用 `5000 + main 分支提交数`；只统计 `main`，不要把当前功能分支提交数算进去。
- 如果目标设备已安装更高 `versionCode` 的临时包，直接覆盖会触发 `INSTALL_FAILED_VERSION_DOWNGRADE`。
- 重复 adb 安装前先检查设备现有 versionCode：

```bash
adb shell dumpsys package lightly.tool | grep versionCode
```

如果新包 versionCode 更低，不要在未确认数据保留策略前卸载清数据；应先确认是否需要临时升高实际 versionCode 或改走手动数据备份/恢复。

## 安装验证

```bash
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

安装后至少验证：

- [ ] 应用能启动。
- [ ] 抽屉或版本展示位置显示 commit-based 版本标签。
- [ ] 浏览器基础加载正常。
- [ ] 设置页可进入。
- [ ] 如果本次涉及远控，receiver/controller 基础链路可用。
- [ ] 如果本次涉及文件简易管理，`http://127.0.0.1:12580` 与局域网地址均可访问，文本文件编辑/删除行为符合预期。

## 常见失败处理

- arm32 R8 内存不足：按 `AGENTS.md` 的 arm32 staged fallback 使用更大 heap 或 no-daemon 重试。
- 第二个 ABI 覆盖第一个 `app-release.apk`：必须立即重命名，脚本已处理。
- Gradle daemon 异常退出：先停止 daemon，再 no-daemon 重试。
- 版本降级安装失败：主分支提交次数版本码低于设备已安装包时，需要先确认保留数据策略，不要直接卸载用户数据。
