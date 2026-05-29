# Release 构建清单

本项目发布 Android APK 时优先使用多 ABI 分包。不要只依赖 `flutter build apk --split-per-abi`，因为仓库内存在手动 `jniLibs/`，需要 `TARGET_ABI` 参与过滤。

## 构建前

- [ ] 工作区已提交，`git status --short` 为空。
- [ ] 确认当前 commit 是要发布的源码版本。
- [ ] 相关自动测试通过。
- [ ] 如触碰 Browser / Remote / Proxy / EasyTier，完成对应回归清单。
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

## 产物检查

- [ ] `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` 存在。
- [ ] `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` 存在。
- [ ] 64 位包只包含 `arm64-v8a` 相关 native slice。
- [ ] 32 位包只包含 `armeabi-v7a` 相关 native slice。
- [ ] `build/app/outputs/symbols/` 存在并与本次构建对应。

## 版本规则

- 用户可见版本标签使用 `vX.Y.Z+<commit>`。
- 不要在 UI 上额外再拼一个 `v`。
- Android `versionCode` 默认直接使用主分支提交次数。
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

## 常见失败处理

- arm32 R8 内存不足：按 `AGENTS.md` 的 arm32 staged fallback 使用更大 heap 或 no-daemon 重试。
- 第二个 ABI 覆盖第一个 `app-release.apk`：必须立即重命名，脚本已处理。
- Gradle daemon 异常退出：先停止 daemon，再 no-daemon 重试。
- 版本降级安装失败：主分支提交次数版本码低于设备已安装包时，需要先确认保留数据策略，不要直接卸载用户数据。
