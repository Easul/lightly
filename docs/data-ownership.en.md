# Lightly Data Ownership Catalog

[中文](data-ownership.md)

## Purpose

This document records the current persistence contracts. Architecture migrations, file moves,
backup, and data clearing must preserve these physical keys, table names, filenames, and deletion
boundaries unless a dedicated compatible migration is provided.

Sensitivity levels: `low` is ordinary app state, `medium` is browsing/device metadata, and `high`
is credentials, private content, or restorable session data.

## SQLite

The physical file remains `browser_data.db`; the current schema version is `4`. Phase 4 renamed the
code owner to `AppDatabase` without changing the filename, table names, or schema.

| Table | Data owner | Sensitivity | Unified backup | Clear/delete contract |
|---|---|---:|---|---|
| `browser_history` | `BrowserHistoryService` (URL summary/title/count) | medium | Yes, up to 1,000 summary rows | Cleared with visits by the History action |
| `browser_history_visits` | `BrowserHistoryService` (individual visits) | medium | No; imported summaries create new visits | Cleared with summaries by the History action |
| `browser_favorites` | `BrowserFavoriteService` | medium | Yes | Favorites clear removes all rows and must invalidate the favorite-status cache |
| `browser_downloads` | `BrowserDownloadStore` | medium | No | Global clear stops tasks and removes records only; per-item deletion may remove the file when explicitly selected |
| `ai_chat_sessions` | `AiHistoryDatabase` | high | No | Deleted per session inside AI chat; session deletion removes its messages first |
| `ai_chat_messages` | `AiHistoryDatabase` | high | No | Deleted with a session or individually inside AI chat; browser-data clearing must not remove it |

AI obtains the shared handle through `AppDatabaseProvider` and owns its table names. `AppDatabase`
executes schema creation without taking ownership of AI data. Contract tests cover the v3-to-v4
upgrade and category-isolated clearing.

## Dart SharedPreferences

Existing physical keys are compatibility contracts and are not renamed by directory/class
refactors. New keys require a feature prefix. Compatible JSON field additions retain the key and
use tolerant defaults; incompatible format changes require a versioned replacement key, an explicit
migration, and deletion of the old key only after migration succeeds. Keys with a `_vN` suffix carry
their version in the name; other historical keys are physical format v0 and stay backward compatible
through their owner's parser.

| Key / key group | Owner / version | Sensitivity | Unified backup | Clear/reset contract |
|---|---|---:|---|---|
| `browser_settings` | `BrowserSettingsService`; historical key v0 with JSON field defaults | high (proxy credentials) | Yes | Import may replace it; resets must go through the settings owner |
| `browser_tab_sessions_v1` | `BrowserTabService`; key version `v1` | medium | No | Owned by session restore; history clearing must preserve it |
| `browser_cookie_origins_v1` | `BrowserCookieOriginService`; key version `v1` | medium | Not directly; drives Cookie origin enumeration | Cleared with cookies/site data, preserved when only history is cleared |
| `browser_subscription_nodes`, `browser_subscription_selected_node` | `BrowserSubscriptionService`; historical key v0 with tolerant node JSON parsing | high | No | Removed/replaced by subscription settings only |
| `clipboard_content`, `clipboard_server_enabled`, `clipboard_server_port` | `ClipboardStorageService`; historical scalar keys v0 | high for content, low for settings | Content and enabled port are backed up | Clipboard clear removes app content only and never changes the Android system clipboard |
| `calculation_history` | `HistoryService`; historical key v0 with tolerant JSON-list parsing | medium | Yes | Cleared by Calculator History |
| `easytier_profiles`, `easytier_selected_profile_id` | `EasyTierProfileService`; historical key v0, profile model owns JSON compatibility | high | Yes | P2P settings remove/replace profiles and repair the selected id |
| `simple_file_manager_settings` | `SimpleFileManagerService`; historical key v0 with JSON field defaults | medium | No | File-manager settings own reset; browser-data clearing preserves it |
| `app_log_enabled` | `AppLogService`; boolean | low | No | Disabling writes `false`, drains queued writes, and deletes `runtime.log` |
| `app_cache_last_cleanup_at_ms` | `AppCacheMaintenanceService`; epoch ms | low | No | Scheduling hint updated after successful cleanup |
| `ai_tools_config` | `AiConfigStore`; historical key v0 with JSON field defaults | high (API key) | No | AI settings replace it; it must not enter logs or ordinary backups |
| `translation_history` | Non-Android `TranslationHistoryStore` fallback; historical key v0, max 200 rows | high | No | Translation-history clear removes it; Android does not read this key |
| `telegram_checkin_config` | `TelegramCheckinStore`; included by backup schema `8` | high | Yes | TG settings/import replace it; never log its secrets |

## Android Native Stores

| Preferences / key | Owner | Sensitivity | Backup | Sync and clear contract |
|---|---|---:|---|---|
| `translation_overlay` / `config` | `TranslationOverlayService` | high | No | Flutter pushes config when starting/updating the overlay; native storage is only a service-restart fallback and never overwrites `AiConfigStore` |
| `translation_overlay` / `history` | Kotlin `TranslationHistoryStore`; max 200 rows | high | No | Android is the history source of truth; Flutter uses the channel for CRUD, and clear removes this key; no automatic merge with the Dart fallback |

System permission grants, VPN state, and overlay/foreground-service state are lifecycle state, not
an app data schema. Stop them through their services/gateways, never by clearing preferences.

## Files And External Data

| Location / data | Owner | Sensitivity | Backup/export | Clear contract |
|---|---|---:|---|---|
| app database path / `browser_data.db` | `AppDatabase` | high | Unified backup serializes selected rows; it does not copy the DB | Repositories clear categories; never delete the whole DB for a partial clear |
| app external `logs/runtime.log` | `AppLogService` | high, sanitized diagnostics | Explicit Log Export copies it to Downloads | Disabling logging drains writes and deletes it |
| shared Downloads or fallback `ruoqing-*.json` | `BrowserBackupFileWriter` | high | It is the user export | The app does not auto-delete exported backups |
| downloaded files in shared Downloads/app fallback | `BrowserDownloadService`; records belong to `BrowserDownloadStore` | file-dependent | Not in unified backup | Global record clear preserves files; only explicit record-plus-file deletion removes one |
| app support `/telegram/` TDLib data | `TelegramTdlibService` / TDLib | high | No | Only explicit Telegram logout/data reset or uninstall may clear it |
| WebView cookies | Android WebView / `CookieManager`; origin index belongs to `BrowserCookieOriginService` | high | Exported per indexed origin where supported | Cookies/Site Data clear removes them; History clear preserves them |
| WebView local/session storage, IndexedDB, Cache API | Android WebView and each origin | high | Unified backup covers only currently enumerable web storage | Global or current-site clear; current-site clear excludes global HTTP cache |
| WebView HTTP cache, app cache, temporary children | `AppCacheMaintenanceService` and WebView APIs | medium | No | App Cache cleanup only; it must preserve history, favorites, downloads, settings, and user files |
| user files under the Simple File Manager root | User; service only provides access | high | No | Only explicit file operations modify/delete them |

## Unified Backup Boundary

The current unified JSON schema version is `8`. It includes favorites, browser settings, up to
1,000 history summaries, calculator history, app clipboard content/enabled port, cookies,
exportable WebStorage, EasyTier profiles/selected id, and Telegram check-in configuration.

It explicitly excludes download records/files, tab sessions, subscription nodes, AI configuration,
AI chat, translation history, file-manager settings, runtime-log state/files, cache timestamps, and
the TDLib database. Adding a category requires a backup schema change, import choice, sensitivity
copy, tests, and an update to this document.

## Change Rules

1. Record owner, schema/version, sensitivity, backup, and clear behavior for all new persisted data.
2. Key/table/file renames require a compatible migration; architecture-only commits do not move physical storage.
3. A feature accesses data through its repository/store or an explicit port, never another feature's concrete store.
4. Clear data by category; never use `SharedPreferences.clear()` or whole-database deletion for partial clearing.
5. Never persist high-sensitivity data in runtime logs, and show the actual path for exported files.
