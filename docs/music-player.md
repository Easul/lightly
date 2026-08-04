# Music Player

The music player is a tool feature under `/music-player`. It has one playback
owner (`MusicPlaybackService` on Android, coordinated by
`MusicPlayerController`) for local files, downloaded files, and resolved online
tracks. Pages only submit playback intent and observe the controller state.

## Storage

Music metadata lives in the existing `browser_data.db` database. Schema version
5 adds `music_tracks` and version 6 adds its `lastPositionMs` column; no second
database is created.

- Owner: `MusicLibraryStore`, with the physical schema owned by `AppDatabase`.
- Key: `trackKey` (`online:<remote-id>` or `local:<content-uri/path>`).
- Data: display metadata, source URI/path, duration, source type, favorite,
  custom group, cached original/translated LRC, update time, last-play time,
  and the remembered playback position.
- Sensitivity: local paths reveal filenames and directories; lyrics and public
  song metadata are not treated as secrets.
- Backup/export: music rows are currently excluded from Lightly's unified
  backup and are rebuilt by scanning or normal use.
- Clear/delete: a device rescan replaces the local-source index while retaining
  favorite/group/lyrics for tracks with the same key. It does not delete audio
  files. Downloaded and online rows are not removed by a local rescan. Explicit
  local-song deletion removes the MediaStore/file item first and deletes its
  database row only after Android confirms the physical deletion. Canceling a
  scoped-storage confirmation keeps the row intact.

The API base URL and key must both be entered manually in Music Settings. They
are stored separately in SharedPreferences under
`music_player_api_base_url_v1` and `music_player_api_key_v1`. Neither value has
a source/build-time default, enters the unified backup, or may be logged.
The base URL may be entered as `https://host/api/` or as a full known endpoint
URL; the client normalizes the latter before appending request parameters.
Search parsing accepts both the compact list response and the Netease-style
nested `data.songs` / `result.songs` response, including `ar` artist and `al`
album metadata.

## Android Runtime

- `MusicPlayerChannelHandler` owns MediaStore scanning, runtime permissions,
  scoped-storage deletion confirmation, external `audio/*` intent metadata,
  and the typed Flutter channel.
- `MusicPlaybackService` owns `MediaPlayer`, `MediaSession`, audio focus, and the
  optional public lock-screen/notification controls.
- `MusicPlayerController` owns the in-memory playback queue and mode. The three
  modes are list loop (default, wraps to the first song), single-song loop, and
  shuffle. A queue comes from the currently filtered group/search list so
  automatic advancement must not cross into a different group.
- The controller also retains the active online search session while the page is
  absent. Search requests use batches of 50; reaching the end appends the next
  batch and extends the active queue only when the current song belongs to that
  search. The page keeps the search field fixed above the scrolling results and
  highlights the active track after automatic or lock-screen advancement.
- Do not query `MediaPlayer` position or duration while it is preparing. Some
  MIUI media stacks report `-38` and enter the error callback when `getDuration()`
  is called in the preparing state.
- Slider dragging is a Flutter-local preview and submits one native seek on
  release. Music downloads stream response chunks to disk and report throttled
  progress rather than buffering the body or rebuilding on every chunk.
- MediaStore `content://` stays authoritative for playback and deletion. When
  volume and relative-path metadata are available, `localPath` carries a derived
  `/storage/...` display path without replacing the content URI.
- Notification and lock-screen controls include previous/play-pause/next. Their
  skip commands return to the controller queue through the typed platform
  gateway. Android resolves local album art and caches bounded remote artwork
  under app cache for `MediaSession` and notification display, with the default
  icon as fallback.
- Disabling the system toolbar removes the foreground notification. Playback
  may then be reclaimed by Android after Lightly leaves the foreground.
- Local, online, and favorite lists reserve bottom scroll padding for the mini
  player and system safe area so the final row can scroll fully into view.
- External audio intents enter the same controller and database path as songs
  selected inside the tool.
- Tapping a track in the local, online, or favorite list replaces the current
  playback immediately. There is no separate downloads page: downloaded songs
  merged with MediaStore rows appear inline in the local list, and downloads
  outside the media library are appended to it.
- Library sort order (added time, name, duration; ascending/descending) is a
  user setting under `music_player_library_sort_v1`. Name sorting compares
  embedded numbers by value so "1, 2, 10" stays in that order.
- Previous/next stay enabled before anything has played: the controller keeps
  the most recently browsed local/favorite/search list as its fallback queue
  and skips within it.
- Each played track remembers its playback position. When a track that has
  finished at least once is tapped again, the app asks whether to continue
  from the remembered position instead of restarting. The resume behavior has
  no user-facing toggle; the top-right sheet only hosts sorting, the system
  playback toolbar switch, and the music settings entry.
- Downloaded files are named with the song title only (no artist prefix).
  Lyrics fetched for a downloaded track are mirrored onto the scanned
  MediaStore row for the same file (matched by stored path, then by file
  name), and `ensureLyrics` reuses lyrics already cached on that scanned row,
  so downloaded songs keep their artwork and lyrics when shown inline in the
  local list. ensurePlayable merges the library copy for the same track key
  before deciding what is missing, so a bare in-memory row (for example right
  after a download finishes) recovers artwork and lyrics already cached under
  its key instead of overwriting them with nulls, and fetches whatever is
  still missing on a best-effort basis without blocking playback or the
  download itself.
- Tapping the system playback notification sends the typed
  `onNotificationOpen` gateway event; the controller resolves any pending
  resume prompt by continuing from the saved position and the app navigates
  straight to the music page.

## Verification

```bash
flutter test test/music/ test/browser/app_database_test.dart
flutter analyze
./gradlew --offline :app:compileDebugKotlin
```

Manual Android checks should cover MediaStore permission/scan, online search and
pagination, play/pause/seek, lyric auto-scroll and tap-to-seek, download path,
external audio opening, notification actions, and notification disable/enable.
