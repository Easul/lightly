# Music Player

The music player is a tool feature under `/music-player`. It has one playback
owner (`MusicPlaybackService` on Android, coordinated by
`MusicPlayerController`) for local files, downloaded files, and resolved online
tracks. Pages only submit playback intent and observe the controller state.

## Storage

Music metadata lives in the existing `browser_data.db` database. Schema version
5 adds `music_tracks`; no second database is created.

- Owner: `MusicLibraryStore`, with the physical schema owned by `AppDatabase`.
- Key: `trackKey` (`online:<remote-id>` or `local:<content-uri/path>`).
- Data: display metadata, source URI/path, duration, source type, favorite,
  custom group, cached original/translated LRC, update time, and last-play time.
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
- Do not query `MediaPlayer` position or duration while it is preparing. Some
  MIUI media stacks report `-38` and enter the error callback when `getDuration()`
  is called in the preparing state.
- Disabling the system toolbar removes the foreground notification. Playback
  may then be reclaimed by Android after Lightly leaves the foreground.
- External audio intents enter the same controller and database path as songs
  selected inside the tool.

## Verification

```bash
flutter test test/music/ test/browser/app_database_test.dart
flutter analyze
./gradlew --offline :app:compileDebugKotlin
```

Manual Android checks should cover MediaStore permission/scan, online search and
pagination, play/pause/seek, lyric auto-scroll and tap-to-seek, download path,
external audio opening, notification actions, and notification disable/enable.
