# EasyTier 状态共享给 Monitor

Lightly 可以把当前 EasyTier / P2P VPN 运行状态通过 Android IPC 暴露给同签名的外部应用。当前目标是让独立的 `monitor` 应用复用 Lightly 已经启动的 EasyTier VPN，避免两个应用同时启动 VPN 造成冲突。

## 访问方式

Lightly 提供只读 `ContentProvider`：

```text
content://lightly.tool.easytier/network_info
```

访问需要声明签名权限：

```xml
<uses-permission android:name="lightly.tool.permission.READ_EASYTIER_STATE" />

<queries>
    <provider android:authorities="lightly.tool.easytier" />
</queries>
```

`READ_EASYTIER_STATE` 的保护级别是 `signature`，因此调用方必须与 Lightly 使用同一个签名证书；否则 Android 会拒绝查询。

## 返回字段

Provider 返回单行 `Cursor`，字段如下：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `instance_name` | String? | Lightly 当前 EasyTier 实例名 |
| `raw_network_info_json` | String? | 原始 `EasyTierJNI.collectNetworkInfos(10)` JSON |
| `virtual_ipv4` | String? | 当前实例的虚拟 IPv4，例如 `10.126.126.22/24` |
| `updated_at` | Long | Lightly 侧缓存更新时间，毫秒时间戳 |
| `is_running` | Int | `1` 表示 EasyTier 实例处于运行状态，`0` 表示未运行或未知 |
| `error_message` | String? | 最近一次刷新状态时的错误信息 |

`raw_network_info_json` 是推荐使用的主字段。它保持 EasyTier 原始 `map[instanceName]` 结构，monitor 可以直接复用现有 `EasyTierNetworkInfoAnalyzer`。

## monitor 查询示例

```kotlin
val uri = Uri.parse("content://lightly.tool.easytier/network_info")

context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
    if (!cursor.moveToFirst()) return@use

    val rawJson = cursor.getString(
        cursor.getColumnIndexOrThrow("raw_network_info_json")
    )
    val instanceName = cursor.getString(
        cursor.getColumnIndexOrThrow("instance_name")
    )
    val virtualIpv4 = cursor.getString(
        cursor.getColumnIndexOrThrow("virtual_ipv4")
    )
    val isRunning = cursor.getInt(
        cursor.getColumnIndexOrThrow("is_running")
    ) == 1

    if (!rawJson.isNullOrBlank()) {
        val root = JSONObject(rawJson)
        val localIp = EasyTierNetworkInfoAnalyzer
            .extractInstanceIpv4(root, instanceName.orEmpty())
            ?.substringBefore('/')
    }
}
```

建议 monitor 在 `EasyTierManager.getNetworkInfo()` 中优先查询该 Provider；如果没有权限、未安装 Lightly、Lightly 未运行 EasyTier、或 `raw_network_info_json` 为空，再回退到 monitor 当前自己的 `EasyTierJNI.collectNetworkInfos(10)` / VPN 扫描逻辑。

## Lightly 侧实现位置

- `android/app/src/main/AndroidManifest.xml`：声明签名权限和 Provider。
- `android/app/src/main/kotlin/lightly/tool/EasyTierInfoProvider.kt`：只读 Provider。
- `android/app/src/main/kotlin/lightly/tool/EasyTierStateStore.kt`：缓存最新 EasyTier 状态。
- `android/app/src/main/kotlin/lightly/tool/MainActivity.kt`：在 EasyTier 启停、轮询和 `getNetworkInfo` 时刷新缓存。

## 验证

Lightly 侧基础验证：

```bash
cd android
./gradlew :app:compileDebugKotlin :app:testDebugUnitTest --tests lightly.tool.EasyTierStateStoreTest
```

真机联调建议：

1. 安装同签名的 Lightly 和 monitor。
2. 在 Lightly 中启动 P2P VPN，等待虚拟 IPv4 出现。
3. 在 monitor 中查询 `content://lightly.tool.easytier/network_info`。
4. 确认 `raw_network_info_json` 非空，并且 monitor 能用其中的 EasyTier peer / route 信息发现被控端。
