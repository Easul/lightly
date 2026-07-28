# Sharing EasyTier State with Monitor

Lightly exposes its current EasyTier / P2P VPN runtime state through Android IPC so a same-signature external app can reuse the VPN that Lightly already started. The immediate consumer is the standalone `monitor` app, which should avoid starting its own VPN when Lightly's VPN is active.

## Access

Lightly provides a read-only `ContentProvider`:

```text
content://lightly.tool.easytier/network_info
```

The caller must request the signature permission:

```xml
<uses-permission android:name="lightly.tool.permission.READ_EASYTIER_STATE" />

<queries>
    <provider android:authorities="lightly.tool.easytier" />
</queries>
```

`READ_EASYTIER_STATE` uses `signature` protection, so the caller must be signed with the same certificate as Lightly. Otherwise Android denies the query.

## Returned Columns

The provider returns a single-row `Cursor`:

| Column | Type | Description |
| --- | --- | --- |
| `instance_name` | String? | Lightly's current EasyTier instance name |
| `raw_network_info_json` | String? | Raw `EasyTierJNI.collectNetworkInfos(10)` JSON |
| `virtual_ipv4` | String? | Current instance virtual IPv4, for example `10.126.126.22/24` |
| `updated_at` | Long | Lightly-side cache update timestamp in milliseconds |
| `is_running` | Int | `1` when the EasyTier instance is running, otherwise `0` |
| `error_message` | String? | Last refresh error, if any |

`raw_network_info_json` is the recommended source of truth. It preserves EasyTier's original `map[instanceName]` structure, so monitor can reuse its existing `EasyTierNetworkInfoAnalyzer`.

## Monitor Query Example

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

Monitor should try this provider first in `EasyTierManager.getNetworkInfo()`. If Lightly is not installed, the permission is missing, EasyTier is not running, or `raw_network_info_json` is blank, fall back to monitor's existing `EasyTierJNI.collectNetworkInfos(10)` or VPN scanning path.

## Lightly and Companion Implementation Files

- `android/app/src/main/AndroidManifest.xml`: retains the same signature-permission declaration for existing monitor compatibility.
- `extensions/easytier/android/app/src/main/AndroidManifest.xml`: declares the provider and the same signature permission in the companion.
- `extensions/easytier/android/app/src/main/kotlin/lightly/tool/plugin/easytier/EasyTierInfoProvider.kt`: companion-owned read-only provider.
- `extensions/easytier/android/app/src/main/kotlin/lightly/tool/plugin/easytier/EasyTierStateStore.kt`: companion-owned latest-state cache.
- `extensions/easytier/android/app/src/main/kotlin/lightly/tool/plugin/easytier/EasyTierRuntimeController.kt`: companion-owned start/stop, polling, and cache refresh.

## Verification

Host and companion baseline checks:

```bash
./gradlew :app:compileDebugKotlin :app:testDebugUnitTest
extensions/telegram/android/gradlew -p extensions/easytier/android --offline :app:testDebugUnitTest
```

Recommended device smoke test:

1. Install same-signature builds of Lightly and monitor.
2. Start P2P VPN in Lightly and wait until a virtual IPv4 is assigned.
3. Query `content://lightly.tool.easytier/network_info` from monitor.
4. Confirm `raw_network_info_json` is non-empty and monitor can use the EasyTier peer / route data to discover controlled devices.
