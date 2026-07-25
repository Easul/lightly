# Lightly 数据所有权清单

[English](data-ownership.en.md)

## 用途

本文记录当前持久化合同。架构迁移、目录移动、备份和数据清理都必须以此表为基线，不能因类名或
feature 目录变化而静默改变物理 key、表名、文件名或清除范围。

敏感级别：`低` 为普通应用状态，`中` 为浏览/设备元数据，`高` 为凭据、私密内容或可恢复会话的数据。

## SQLite

物理文件固定为 `browser_data.db`，当前 schema version 为 `4`。代码 owner 已在 Phase 4 改名为
`AppDatabase`；该改名没有改变文件名、表名或 schema。

| 表 | 数据 owner | 敏感 | 统一备份 | 清除/删除合同 |
|---|---|---:|---|---|
| `browser_history` | `BrowserHistoryService`（URL 聚合、标题、次数） | 中 | 是，最多导出 1000 条聚合记录 | “历史浏览”清除时与 visits 一起删除 |
| `browser_history_visits` | `BrowserHistoryService`（逐次访问） | 中 | 否；导入历史会重新产生访问记录 | “历史浏览”清除时与 summary 一起删除 |
| `browser_favorites` | `BrowserFavoriteService` | 中 | 是 | “收藏”可全量清除；清除后必须失效 favorite status cache |
| `browser_downloads` | `BrowserDownloadStore` | 中 | 否 | 全局清除只删记录并停止任务，不删磁盘文件；单条删除由用户选择是否连文件一起删 |
| `ai_chat_sessions` | `AiHistoryDatabase` | 高 | 否 | AI 聊天内按会话删除；删除会话时先删对应消息 |
| `ai_chat_messages` | `AiHistoryDatabase` | 高 | 否 | 随会话删除或在 AI 聊天内单条删除；不得被浏览数据清理误删 |

AI 通过 `AppDatabaseProvider` 获取共享句柄；表名仍由 AI feature 持有。SQLite schema 创建由
`AppDatabase` 执行，但这不改变上述数据 owner。v3 到 v4 升级与按类别隔离清理已有合同测试。

## Dart SharedPreferences

Flutter `shared_preferences` 在 Android 上落到应用私有 preferences。下表按 key 组列出全部当前 owner。
现有物理 key 均为兼容合同，不因目录或类名重构而改名。新 key 必须带 feature 前缀；兼容的 JSON
字段扩展保留原 key 并使用容错默认值，破坏性格式变更必须使用带版本的新 key、显式迁移，并在确认
迁移成功后再删除旧 key。带 `_vN` 后缀的 key，其版本由 key 名负责；其余历史 key 视为物理格式 v0，
由 owner 的解析器保持向后兼容。

| Key / key 组 | Owner / 版本 | 敏感 | 统一备份 | 清除/重置合同 |
|---|---|---:|---|---|
| `browser_settings` | `BrowserSettingsService`；历史 key v0，JSON 字段默认值兼容 | 高（含代理凭据） | 是 | 导入可覆盖；无独立“清除全部设置”，重置必须走 settings owner |
| `browser_tab_sessions_v1` | `BrowserTabService`；key 版本 `v1` | 中 | 否 | 会话恢复 owner 自行覆盖；清浏览历史不得删除 tab session |
| `browser_cookie_origins_v1` | `BrowserCookieOriginService`；key 版本 `v1` | 中 | 不直接备份；用于枚举 Cookie 导出 origin | 清 Cookie/站点数据时清除；只清历史时保留 |
| `browser_subscription_nodes`, `browser_subscription_selected_node` | `BrowserSubscriptionService`；历史 key v0，节点 JSON 容错读取 | 高（订阅节点可能含凭据） | 否 | 由订阅设置删除/覆盖；不得随历史清理删除 |
| `clipboard_content`, `clipboard_server_enabled`, `clipboard_server_port` | `ClipboardStorageService`；历史标量 key v0 | 高（内容）、低（开关/端口） | 内容与启用时端口会备份；enabled 不独立导出 | “剪贴板”清除只清 app 保存内容；不得清 Android 系统剪贴板；服务设置由 owner 更新 |
| `calculation_history` | `HistoryService`；历史 key v0，JSON list 容错读取 | 中 | 是 | “计算器历史”全量清除 |
| `easytier_profiles`, `easytier_selected_profile_id` | `EasyTierProfileService`；历史 key v0，profile model 负责 JSON 兼容 | 高（网络 secret/peer） | 是 | P2P 设置中删除/覆盖；删除选中 profile 时 owner 修正 selected id |
| `simple_file_manager_settings` | `SimpleFileManagerService`；历史 key v0，JSON 字段默认值兼容 | 中（根路径、服务设置） | 否 | 文件管理设置保存/重置；清浏览数据不得影响运行配置 |
| `app_log_enabled` | `AppLogService`；布尔值 | 低 | 否 | 关闭记录时写 `false`、等待队列并删除 `runtime.log` |
| `app_cache_last_cleanup_at_ms` | `AppCacheMaintenanceService`；epoch ms | 低 | 否 | 仅调度提示；缓存清理成功后更新，设置导入不覆盖 |
| `ai_tools_config` | `AiConfigStore`；历史 key v0，JSON 字段默认值兼容 | 高（API key） | 否 | AI 设置保存/覆盖；不得写入日志或普通备份 |
| `translation_history` | `TranslationHistoryStore` 非 Android fallback；历史 key v0，最多 200 条 | 高（原文/译文） | 否 | 翻译历史清除；Android 上不读取此 key |
| `telegram_checkin_config` | `TelegramCheckinStore`；backup schema version `8` 包含该对象 | 高（App ID/hash、手机号、目标/命令） | 是 | TG 设置保存/覆盖；不得记录到 runtime log |

## Android 原生存储

| Preferences / key | Owner | 敏感 | 备份 | 同步与清除合同 |
|---|---|---:|---|---|
| `translation_overlay` / `config` | `TranslationOverlayService` | 高（AI API 配置） | 否 | Flutter 每次启动/更新悬浮翻译时单向下发；原生只作为后台 service 重启 fallback，不反向覆盖 `AiConfigStore` |
| `translation_overlay` / `history` | `TranslationHistoryStore` (Kotlin)，最多 200 条 | 高 | 否 | Android 是翻译历史 source of truth；Flutter 通过 channel 增删改查，clear 删除此 key；与 Dart fallback 不自动双向合并 |

Android 系统保存的权限授予、VPN 状态和 overlay/foreground-service 状态不是应用数据 schema，不能通过
SharedPreferences 清理来模拟停止；必须调用各自 service/gateway 的生命周期 API。

## 文件、系统存储与外部数据

| 位置 / 数据 | Owner | 敏感 | 备份/导出 | 清除合同 |
|---|---|---:|---|---|
| app database path / `browser_data.db` | `AppDatabase` | 高 | 仅由统一备份选择性序列化部分表，不复制 DB 文件 | 由各 repository 按类别清理，不整库删除 |
| app external `logs/runtime.log` | `AppLogService` | 高（已脱敏诊断） | 用户显式“导出日志”时复制到 Download | 关闭 runtime logging 时等待写队列后删除；缓存清理不负责删除 |
| shared Download 或 app fallback 下的 `ruoqing-*.json` | `BrowserBackupFileWriter` | 高（备份含 Cookie、配置与私密内容） | 文件本身就是用户导出物 | 应用不自动删除；由用户/文件管理器处理 |
| shared Download / app fallback 下载文件 | `BrowserDownloadService`（记录由 `BrowserDownloadStore`） | 取决于文件 | 不进入统一备份 | 全局清记录保留文件；单条“记录+文件”才删除对应文件 |
| app support `/telegram/`（TDLib database/files） | `TelegramTdlibService` / TDLib | 高（登录会话、聊天缓存） | 否 | 仅由明确的 Telegram logout/data reset 流程或卸载清除；普通 TG 配置、浏览数据清理不得删除 |
| WebView Cookie store | Android WebView / `CookieManager`，origin index 由 `BrowserCookieOriginService` 持有 | 高 | 统一备份按 origin 枚举并导出支持的 Cookie | “Cookie 与站点数据”清除；清历史不清 Cookie |
| WebView local/session storage、IndexedDB、Cache API | Android WebView + 当前 WebView origin | 高 | 统一备份仅覆盖当前实现可枚举的 web storage | 全局站点数据或当前站点清理；当前站点清理不含 WebView 全局 HTTP cache |
| WebView 全局 HTTP cache / app cache / temp children | `AppCacheMaintenanceService` 与 WebView API | 中 | 否 | “清理应用缓存”或计划清理；不得清历史、收藏、下载记录、配置或用户文件 |
| Simple file manager root 中的用户文件 | 用户；`SimpleFileManagerService` 只提供访问 | 高 | 否 | 仅用户明确文件操作可改删；停止服务或清 app cache 不得删除 |

## 统一备份边界

当前统一备份 JSON schema version 为 `8`，包括：收藏、浏览设置、最多 1000 条历史聚合、计算器
历史、app 剪贴板内容/启用时端口、Cookie、可导出的 WebStorage、EasyTier profiles/selected id、
Telegram 签到配置。

明确不包括：下载记录和文件、tab session、订阅节点、AI 配置、AI 聊天、翻译历史、文件管理设置、
日志开关/文件、缓存调度时间、TDLib 数据库。增加任一数据类别前必须同时更新 backup schema、导入
选择、敏感提示、测试和本文。

## 变更规则

1. 新增持久化数据时同时记录 owner、schema/version、敏感级别、备份与清除行为。
2. 改 key、表名或文件名必须提供兼容迁移；纯架构重构不得顺带迁移物理存储。
3. feature 只能通过自己的 repository/store 或明确 port 访问数据，不能依赖另一 feature 的具体存储类。
4. 数据清理按类别执行；禁止用 `SharedPreferences.clear()` 或删整库实现局部清理。
5. 高敏数据不得写入 runtime log；导出文件必须明确提示实际保存路径。
