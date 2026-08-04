import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lightly/browser/data/app_database.dart';
import 'package:lightly/browser/data/app_database_adapter.dart';
import 'package:lightly/features/music/domain/music_lyric.dart';
import 'package:lightly/features/music/domain/music_library_sort.dart';
import 'package:lightly/features/music/domain/music_track.dart';
import 'package:lightly/features/music/application/music_player_controller.dart';
import 'package:lightly/features/music/infrastructure/music_api_client.dart';
import 'package:lightly/features/music/infrastructure/music_library_store.dart';
import 'package:lightly/features/music/infrastructure/music_platform_gateway.dart';
import 'package:lightly/features/music/infrastructure/music_settings_store.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Music natural title sorting', () {
    test('orders embedded numbers by value, not lexicographically', () {
      expect(compareMusicTitles('1', '10'), lessThan(0));
      expect(compareMusicTitles('2', '10'), lessThan(0));
      expect(compareMusicTitles('第 10 首', '第 2 首'), greaterThan(0));
    });

    test('sorts name ascending and descending around non-numeric titles', () {
      MusicTrack named(String title) => MusicTrack(
        trackKey: 'local:$title',
        title: title,
        artist: '歌手',
        album: '专辑',
        sourceUri: 'content://song/$title',
        sourceType: MusicSourceType.local,
      );
      final tracks = <MusicTrack>[
        named('10'),
        named('晴天'),
        named('2'),
        named('1'),
      ];

      final ascending = sortMusicTracks(
        tracks,
        const MusicLibrarySort(
          field: MusicSortField.name,
          order: MusicSortOrder.ascending,
        ),
      );
      expect(ascending.map((track) => track.title), ['1', '2', '10', '晴天']);

      final descending = sortMusicTracks(
        tracks,
        const MusicLibrarySort(
          field: MusicSortField.name,
          order: MusicSortOrder.descending,
        ),
      );
      expect(descending.map((track) => track.title), ['晴天', '10', '2', '1']);
    });

    test('parses stored sort values with a safe fallback', () {
      const sort = MusicLibrarySort(
        field: MusicSortField.duration,
        order: MusicSortOrder.ascending,
      );
      final parsed = MusicLibrarySort.parse(sort.storageValue);
      expect(parsed.field, MusicSortField.duration);
      expect(parsed.order, MusicSortOrder.ascending);
      expect(MusicLibrarySort.parse('garbage').field, MusicSortField.addedTime);
    });
  });

  group('LRC parser', () {
    test('parses multiple timestamps and finds active line', () {
      final lines = parseLrc('''
[00:01.20][00:03.400]第一句
[00:05.00]第二句
[ar:歌手]
''');

      expect(lines.map((line) => line.time.inMilliseconds), [1200, 3400, 5000]);
      expect(lines.map((line) => line.text), ['第一句', '第一句', '第二句']);
      expect(activeLyricIndex(lines, const Duration(milliseconds: 3399)), 0);
      expect(activeLyricIndex(lines, const Duration(milliseconds: 3400)), 1);
      expect(activeLyricIndex(lines, const Duration(seconds: 8)), 2);
    });
  });

  group('Music API client', () {
    test('uses documented pagination and maps search fields', () async {
      late Uri requestedUri;
      late Map<String, String> requestedHeaders;
      final client = MusicApiClient(
        client: MockClient((request) async {
          requestedUri = request.url;
          requestedHeaders = request.headers;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'code': 200,
                'msg': 'success',
                'data': <Object?>[
                  <String, Object?>{
                    'id': 1315196858,
                    'name': '海底',
                    'artists': '一支榴莲',
                    'album': '独',
                    'picUrl': 'https://image.test/cover.jpg',
                  },
                ],
                'total': 300,
              }),
            ),
            200,
          );
        }),
      );

      final result = await client.search(
        apiBaseUrl: 'https://music.test/api',
        keyword: '海底',
        page: 2,
        apiKey: 'key',
      );

      expect(requestedUri.path, '/api/163_search');
      expect(requestedUri.queryParameters['limit'], '50');
      expect(requestedUri.queryParameters['offset'], '50');
      expect(requestedUri.queryParameters['keyword'], '海底');
      expect(requestedHeaders['User-Agent'], contains('Firefox/153.0'));
      expect(requestedHeaders['Accept-Encoding'], 'gzip');
      expect(result.total, 300);
      expect(result.tracks.single.title, '海底');
      expect(result.tracks.single.artist, '一支榴莲');
      expect(result.tracks.single.album, '独');
    });

    test('rejects an invalid manually entered API URL', () async {
      final client = MusicApiClient(
        client: MockClient((request) async => http.Response('{}', 200)),
      );

      expect(
        () => client.search(
          apiBaseUrl: 'not-a-url',
          keyword: 'test',
          page: 1,
          apiKey: 'key',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts a full endpoint URL without duplicating its path', () async {
      late Uri requestedUri;
      final client = MusicApiClient(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response(
            jsonEncode(<String, Object?>{'code': 200, 'data': <Object?>[]}),
            200,
          );
        }),
      );

      await client.search(
        apiBaseUrl: 'https://music.test/api/163_search?old=query',
        keyword: 'test',
        page: 1,
        apiKey: 'key',
      );

      expect(requestedUri.path, '/api/163_search');
    });

    test('maps nested Netease-style search payloads', () async {
      final client = MusicApiClient(
        client: MockClient(
          (request) async => http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'code': 200,
                'data': <String, Object?>{
                  'songCount': 1,
                  'songs': <Object?>[
                    <String, Object?>{
                      'id': 7,
                      'name': '清明雨上',
                      'ar': <Object?>[
                        <String, Object?>{'name': '许嵩'},
                      ],
                      'al': <String, Object?>{
                        'name': '自定义专辑',
                        'picUrl': 'https://image.test/cover.jpg',
                      },
                    },
                  ],
                },
              }),
            ),
            200,
          ),
        ),
      );

      final result = await client.search(
        apiBaseUrl: 'https://music.test/api/',
        keyword: '清明雨上',
        page: 1,
        apiKey: 'key',
      );

      expect(result.total, 1);
      expect(result.tracks.single.artist, '许嵩');
      expect(result.tracks.single.album, '自定义专辑');
      expect(result.tracks.single.artworkUrl, contains('cover.jpg'));
    });

    test('surfaces a bounded server authentication message', () async {
      final client = MusicApiClient(
        client: MockClient(
          (request) async => http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'code': 401,
                'msg': '缺少 apikey 参数，请先登录并查看个人密钥',
              }),
            ),
            401,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          ),
        ),
      );

      await expectLater(
        client.search(
          apiBaseUrl: 'https://music.test/api',
          keyword: 'test',
          page: 1,
          apiKey: '',
        ),
        throwsA(
          predicate(
            (error) =>
                error is MusicApiException &&
                error.message.contains('缺少 apikey 参数'),
          ),
        ),
      );
    });
  });

  group('Music settings', () {
    test('API URL and key are empty until the user saves them', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final settings = await const MusicSettingsStore().load();

      expect(settings.apiBaseUrl, isEmpty);
      expect(settings.apiKey, isEmpty);
    });

    test('persists the manually entered API URL and key', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = MusicSettingsStore();

      await store.save(
        const MusicSettings(
          apiBaseUrl: 'https://music.test/api/',
          apiKey: 'manual-key',
          quality: 'lossless',
          notificationEnabled: false,
          resumePromptEnabled: false,
          librarySort: MusicLibrarySort(
            field: MusicSortField.name,
            order: MusicSortOrder.ascending,
          ),
        ),
      );

      final settings = await store.load();
      expect(settings.apiBaseUrl, 'https://music.test/api/');
      expect(settings.apiKey, 'manual-key');
      expect(settings.quality, 'lossless');
      expect(settings.notificationEnabled, isFalse);
      expect(settings.resumePromptEnabled, isFalse);
      expect(settings.librarySort.field, MusicSortField.name);
      expect(settings.librarySort.order, MusicSortOrder.ascending);
    });

    test('defaults resume prompt on and library sort to added time', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final settings = await const MusicSettingsStore().load();

      expect(settings.resumePromptEnabled, isTrue);
      expect(settings.librarySort.field, MusicSortField.addedTime);
      expect(settings.librarySort.order, MusicSortOrder.descending);
    });
  });

  group('Music library in shared database', () {
    late String databasePath;
    late AppDatabase database;
    late MusicLibraryStore store;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      databasePath = path.join(
        await getDatabasesPath(),
        'music_test_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      database = AppDatabase.forTesting(databasePath);
      store = MusicLibraryStore(
        database: AppDatabaseAdapter(database: database),
      );
    });

    tearDown(() async {
      await database.close();
      await databaseFactory.deleteDatabase(databasePath);
    });

    test(
      'rescan updates metadata while preserving user state and lyrics',
      () async {
        const initial = MusicTrack(
          trackKey: 'local:content://song/1',
          title: '旧标题',
          artist: '歌手',
          album: '专辑',
          sourceUri: 'content://song/1',
          sourceType: MusicSourceType.local,
          isFavorite: true,
          groupName: '通勤',
          lyric: '[00:01.00]歌词',
        );
        await store.save(initial);

        await store.replaceLocalTracks(const <MusicTrack>[
          MusicTrack(
            trackKey: 'local:content://song/1',
            title: '新标题',
            artist: '歌手',
            album: '新专辑',
            sourceUri: 'content://song/1',
            sourceType: MusicSourceType.local,
            durationMs: 1234,
          ),
        ]);

        final track = await store.get(initial.trackKey);
        expect(track?.title, '新标题');
        expect(track?.durationMs, 1234);
        expect(track?.isFavorite, isTrue);
        expect(track?.groupName, '通勤');
        expect(track?.lyric, '[00:01.00]歌词');
        expect(await store.listGroups(), ['通勤']);

        final stored = await store.get(initial.trackKey);
        await store.replaceLocalTracks(const <MusicTrack>[
          MusicTrack(
            trackKey: 'local:content://song/1',
            title: '再次扫描标题',
            artist: '歌手',
            album: '新专辑',
            sourceUri: 'content://song/1',
            sourceType: MusicSourceType.local,
            durationMs: 1234,
          ),
        ]);
        final rescanned = await store.get(initial.trackKey);
        expect(rescanned?.updatedAt, stored?.updatedAt);
      },
    );

    test('deletes one music record by its stable track key', () async {
      const track = MusicTrack(
        trackKey: 'local:content://song/2',
        title: '待删除',
        artist: '歌手',
        album: '专辑',
        sourceUri: 'content://song/2',
        sourceType: MusicSourceType.local,
      );
      await store.save(track);

      await store.delete(track.trackKey);

      expect(await store.get(track.trackKey), isNull);
    });

    test(
      'matches a downloaded file to its scanned row by path or file name',
      () async {
        const path = '/storage/emulated/0/Download/music/海底.mp3';
        const scanned = MusicTrack(
          trackKey: 'local:content://media/external/audio/media/42',
          title: '海底',
          artist: '歌手',
          album: '专辑',
          sourceUri: 'content://media/external/audio/media/42',
          localPath: path,
          sourceType: MusicSourceType.local,
          lyric: '[00:01.00]扫描行歌词',
        );
        await store.save(scanned);

        final byPath = await store.getMatchingLocalTrack(path);
        expect(byPath?.trackKey, scanned.trackKey);

        const renamedScanned = MusicTrack(
          trackKey: 'local:content://media/external/audio/media/43',
          title: '光年之外',
          artist: '歌手',
          album: '专辑',
          sourceUri: 'content://media/external/audio/media/43',
          localPath: '/storage/emulated/0/Music/光年之外.mp3',
          sourceType: MusicSourceType.local,
        );
        await store.save(renamedScanned);

        final byName = await store.getMatchingLocalTrack(
          '/storage/emulated/0/Download/music/光年之外.mp3',
        );
        expect(byName?.trackKey, renamedScanned.trackKey);

        final missing = await store.getMatchingLocalTrack(
          '/storage/emulated/0/Download/music/不存在.mp3',
        );
        expect(missing, isNull);
      },
    );

    test('merges downloaded tracks with scanned device rows', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const channel = MethodChannel('music_downloaded_queue_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getState') {
              return <String, Object?>{
                'trackKey': '',
                'playing': false,
                'buffering': false,
              };
            }
            if (call.method == 'resolveLocalMetadata') {
              return <String, Object?>{
                'uri': 'content://media/external/audio/media/11',
              };
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      const downloaded = MusicTrack(
        trackKey: 'online:55',
        remoteId: '55',
        title: '下载歌曲',
        artist: '歌手',
        album: '专辑',
        sourceUri: 'file:///storage/emulated/0/Download/music/a.mp3',
        localPath: '/storage/emulated/0/Download/music/a.mp3',
        sourceType: MusicSourceType.downloaded,
        lyric: '[00:01.00]下载歌词',
        artworkUrl: 'https://image.test/cover.jpg',
      );
      const scanned = MusicTrack(
        trackKey: 'local:/storage/emulated/0/Download/music/a.mp3',
        title: '扫描标题',
        artist: '歌手',
        album: '专辑',
        sourceUri: 'content://media/external/audio/media/11',
        localPath: '/storage/emulated/0/Download/music/a.mp3',
        sourceType: MusicSourceType.local,
      );
      await store.save(downloaded);
      await store.save(scanned);
      final controller = MusicPlayerController(
        platform: MusicPlatformGateway(channel: channel),
        library: store,
      );

      await controller.initialize();

      expect(controller.downloadedQueue, hasLength(1));
      final merged = controller.downloadedQueue.single;
      expect(merged.trackKey, scanned.trackKey);
      expect(merged.lyric, downloaded.lyric);
      expect(merged.artworkUrl, downloaded.artworkUrl);

      await controller.playTrack(merged);

      expect(controller.currentTrack?.trackKey, scanned.trackKey);
      expect(await store.get('online:55'), isNotNull);
    });

    test('ensureLyrics recovers artwork cached on the library copy and mirrors '
        'metadata onto the scanned row', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'music_player_api_base_url_v1': 'https://music.test/api/',
        'music_player_api_key_v1': 'key',
      });
      const channel = MethodChannel('music_metadata_recover_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getState') {
              return <String, Object?>{
                'trackKey': '',
                'playing': false,
                'buffering': false,
              };
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      const path = '/storage/emulated/0/Download/music/无损.mp3';
      const cached = MusicTrack(
        trackKey: 'online:77',
        remoteId: '77',
        title: '无损',
        artist: '歌手',
        album: '专辑',
        sourceUri: 'file://$path',
        localPath: path,
        sourceType: MusicSourceType.downloaded,
        artworkUrl: 'https://image.test/cover-77.jpg',
      );
      const scanned = MusicTrack(
        trackKey: 'local:$path',
        title: '无损',
        artist: '歌手',
        album: '专辑',
        sourceUri: 'content://media/external/audio/media/77',
        localPath: path,
        sourceType: MusicSourceType.local,
      );
      await store.save(cached);
      await store.save(scanned);
      var lyricRequests = 0;
      var artworkRequests = 0;
      final api = MusicApiClient(
        client: MockClient((request) async {
          final body = switch (request.url.path) {
            '/api/163_lyric' => () {
              lyricRequests++;
              return jsonEncode(<String, Object?>{
                'code': 200,
                'data': <String, Object?>{'lrc': '[00:01.00]恢复歌词'},
              });
            }(),
            '/api/163_music' => () {
              artworkRequests++;
              return jsonEncode(<String, Object?>{
                'code': 200,
                'data': <String, Object?>{'picUrl': null},
              });
            }(),
            _ => '{}',
          };
          return http.Response.bytes(utf8.encode(body), 200);
        }),
      );
      final controller = MusicPlayerController(
        platform: MusicPlatformGateway(channel: channel),
        api: api,
        library: store,
      );

      // A bare in-memory row, as the download page holds right after the
      // file finished downloading: no lyric, no artwork.
      const bare = MusicTrack(
        trackKey: 'online:77',
        remoteId: '77',
        title: '无损',
        artist: '歌手',
        album: '专辑',
        sourceUri: 'file://$path',
        localPath: path,
        sourceType: MusicSourceType.downloaded,
      );
      final recovered = await controller.ensureLyrics(bare);

      expect(recovered.lyric, '[00:01.00]恢复歌词');
      expect(recovered.artworkUrl, 'https://image.test/cover-77.jpg');
      expect(lyricRequests, 1);
      expect(artworkRequests, 0);

      final mirrored = await store.get(scanned.trackKey);
      expect(mirrored?.lyric, '[00:01.00]恢复歌词');
      expect(mirrored?.artworkUrl, 'https://image.test/cover-77.jpg');
    });

    test('ensureLyrics reuses lyrics cached under a different key for the same '
        'remote id and backfills every copy', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'music_player_api_base_url_v1': 'https://music.test/api/',
        'music_player_api_key_v1': 'key',
      });
      const channel = MethodChannel('music_metadata_backfill_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getState') {
              return <String, Object?>{
                'trackKey': '',
                'playing': false,
                'buffering': false,
              };
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      const onlineRow = MusicTrack(
        trackKey: 'online:88',
        remoteId: '88',
        title: '缓存歌',
        artist: '歌手',
        album: '专辑',
        sourceUri: 'https://cdn.test/88.mp3',
        sourceType: MusicSourceType.online,
        lyric: '[00:01.00]在线行歌词',
        artworkUrl: 'https://image.test/cover-88.jpg',
      );
      const bareDownload = MusicTrack(
        trackKey: 'downloaded:88',
        remoteId: '88',
        title: '缓存歌',
        artist: '歌手',
        album: '专辑',
        sourceUri: 'file:///storage/emulated/0/Download/歌手-缓存歌.mp3',
        localPath: '/storage/emulated/0/Download/歌手-缓存歌.mp3',
        sourceType: MusicSourceType.downloaded,
      );
      await store.save(onlineRow);
      await store.save(bareDownload);
      final probe = await store.listByRemoteId('88');
      expect(probe, hasLength(2));
      var apiCalls = 0;
      final controller = MusicPlayerController(
        platform: MusicPlatformGateway(channel: channel),
        metadata: _CountingMetadataResolver(onCall: () => apiCalls++),
        library: store,
      );

      final recovered = await controller.ensureLyrics(bareDownload);

      expect(recovered.lyric, '[00:01.00]在线行歌词');
      expect(recovered.artworkUrl, 'https://image.test/cover-88.jpg');
      // Everything came from the other key's cache: no network needed.
      expect(apiCalls, 0);

      final storedDownload = await store.get(bareDownload.trackKey);
      expect(storedDownload?.lyric, '[00:01.00]在线行歌词');
      expect(storedDownload?.artworkUrl, 'https://image.test/cover-88.jpg');
    });

    test('cycles within the current queue for all playback modes', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const channel = MethodChannel('music_mode_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getState') {
              return <String, Object?>{
                'trackKey': '',
                'playing': false,
                'buffering': false,
              };
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final controller = MusicPlayerController(
        platform: MusicPlatformGateway(channel: channel),
        library: store,
      );
      const first = MusicTrack(
        trackKey: 'local:file:///first.mp3',
        title: '第一首',
        artist: '歌手',
        album: '专辑',
        sourceUri: 'file:///first.mp3',
        sourceType: MusicSourceType.local,
      );
      const second = MusicTrack(
        trackKey: 'local:file:///second.mp3',
        title: '第二首',
        artist: '歌手',
        album: '专辑',
        sourceUri: 'file:///second.mp3',
        sourceType: MusicSourceType.local,
      );

      await controller.initialize();
      await controller.playTrack(
        second,
        queue: const <MusicTrack>[first, second],
      );
      await controller.next();
      expect(controller.currentTrack?.trackKey, first.trackKey);

      controller.cyclePlaybackMode();
      expect(controller.playbackMode, MusicPlaybackMode.singleLoop);
      await controller.next();
      expect(controller.currentTrack?.trackKey, first.trackKey);

      controller.cyclePlaybackMode();
      expect(controller.playbackMode, MusicPlaybackMode.shuffle);
      await controller.next();
      expect(controller.currentTrack?.trackKey, second.trackKey);
    });

    test('keeps and incrementally extends the active search session', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'music_player_api_base_url_v1': 'https://music.test/api/',
        'music_player_api_key_v1': 'key',
      });
      const channel = MethodChannel('music_search_session_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getState') {
              return <String, Object?>{
                'trackKey': '',
                'playing': false,
                'buffering': false,
              };
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final api = MusicApiClient(
        client: MockClient((request) async {
          final offset = int.parse(request.url.queryParameters['offset']!);
          final count = offset == 0 ? 50 : 1;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'code': 200,
                'total': 51,
                'data': List<Object?>.generate(
                  count,
                  (index) => <String, Object?>{
                    'id': offset + index,
                    'name': '歌曲 ${offset + index}',
                    'artist': '歌手',
                    'album': '专辑',
                  },
                ),
              }),
            ),
            200,
          );
        }),
      );
      final controller = MusicPlayerController(
        platform: MusicPlatformGateway(channel: channel),
        api: api,
        library: store,
      );

      await controller.search('保留的搜索');

      expect(controller.searchKeyword, '保留的搜索');
      expect(controller.searchResults, hasLength(50));
      expect(controller.searchHasMore, isTrue);

      await controller.loadMoreSearchResults();

      expect(controller.searchResults, hasLength(51));
      expect(controller.searchHasMore, isFalse);

      controller.clearSearch();
      expect(controller.searchKeyword, isEmpty);
      expect(controller.searchResults, isEmpty);
    });

    test('remembers playback position across queue switches', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const channel = MethodChannel('music_resume_position_test');
      final playCalls = <Map<Object?, Object?>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getState') {
              return <String, Object?>{
                'trackKey': '',
                'playing': false,
                'buffering': false,
              };
            }
            if (call.method == 'play') {
              playCalls.add(call.arguments as Map<Object?, Object?>);
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final controller = MusicPlayerController(
        platform: MusicPlatformGateway(channel: channel),
        library: store,
      );
      const first = MusicTrack(
        trackKey: 'local:content://song/one',
        title: '第一首',
        artist: '歌手',
        album: '专辑',
        sourceUri: 'content://song/one',
        sourceType: MusicSourceType.local,
      );
      const second = MusicTrack(
        trackKey: 'local:content://song/two',
        title: '第二首',
        artist: '歌手',
        album: '专辑',
        sourceUri: 'content://song/two',
        sourceType: MusicSourceType.local,
      );
      const queue = <MusicTrack>[first, second];

      await controller.initialize();
      await controller.playTrack(first, queue: queue);
      controller.simulatePlaybackStateForTesting(
        trackKey: first.trackKey,
        playing: true,
        positionMs: 83000,
        durationMs: 200000,
      );
      await controller.playTrack(second);

      final remembered = await store.get(first.trackKey);
      expect(remembered?.lastPositionMs, 83000);
      expect(remembered?.lastPlayedAt, isNotNull);

      await controller.playFromLibrary(first, queue);

      expect(controller.resumeRequestChanges.value, isNotNull);
      expect(playCalls, hasLength(2));

      await controller.resolveResumeRequest(true);

      expect(playCalls, hasLength(3));
      expect(playCalls.last['positionMs'], 83000);
      expect(playCalls.last['trackKey'], first.trackKey);
      expect(controller.currentTrack?.trackKey, first.trackKey);
      expect(controller.queue.length, 2);
    });

    test(
      'resume toggle off starts from the beginning without prompting',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'music_player_resume_prompt_v1': false,
        });
        const channel = MethodChannel('music_resume_disabled_test');
        final playCalls = <Map<Object?, Object?>>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'getState') {
                return <String, Object?>{
                  'trackKey': '',
                  'playing': false,
                  'buffering': false,
                };
              }
              if (call.method == 'play') {
                playCalls.add(call.arguments as Map<Object?, Object?>);
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        final controller = MusicPlayerController(
          platform: MusicPlatformGateway(channel: channel),
          library: store,
        );
        const track = MusicTrack(
          trackKey: 'local:content://song/resume-off',
          title: '老歌',
          artist: '歌手',
          album: '专辑',
          sourceUri: 'content://song/resume-off',
          sourceType: MusicSourceType.local,
        );
        await store.save(
          track.copyWith(lastPlayedAt: DateTime.now(), lastPositionMs: 42000),
        );

        await controller.initialize();
        await controller.playFromLibrary(track, const <MusicTrack>[track]);

        expect(controller.resumeRequestChanges.value, isNull);
        expect(playCalls.single['positionMs'], 0);
      },
    );

    test(
      'previous and next work before playback using the browse queue',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        const channel = MethodChannel('music_browse_queue_test');
        final playCalls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'getState') {
                return <String, Object?>{
                  'trackKey': '',
                  'playing': false,
                  'buffering': false,
                };
              }
              if (call.method == 'play') {
                playCalls.add('${(call.arguments as Map)['trackKey']}');
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        final controller = MusicPlayerController(
          platform: MusicPlatformGateway(channel: channel),
          library: store,
        );
        MusicTrack local(String name) => MusicTrack(
          trackKey: 'local:' + name,
          title: name,
          artist: '歌手',
          album: '专辑',
          sourceUri: 'content://song/' + name,
          sourceType: MusicSourceType.local,
        );
        final tracks = <MusicTrack>[local('1'), local('2'), local('10')];

        await controller.initialize();
        expect(controller.hasNext, isFalse);

        controller.registerBrowseQueue(tracks);

        expect(controller.hasPrevious, isTrue);
        expect(controller.hasNext, isTrue);

        await controller.next();
        expect(playCalls, ['local:2']);

        await controller.next();
        expect(playCalls, ['local:2', 'local:10']);

        await controller.previous();
        expect(playCalls, ['local:2', 'local:10', 'local:2']);
      },
    );

    test(
      'opening the system notification resumes a pending saved position',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        const channel = MethodChannel('music_notification_open_test');
        final playCalls = <Map<Object?, Object?>>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'getState') {
                return <String, Object?>{
                  'trackKey': '',
                  'playing': false,
                  'buffering': false,
                };
              }
              if (call.method == 'play') {
                playCalls.add(call.arguments as Map<Object?, Object?>);
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        final controller = MusicPlayerController(
          platform: MusicPlatformGateway(channel: channel),
          library: store,
        );
        const track = MusicTrack(
          trackKey: 'local:content://song/notify',
          title: '通知歌曲',
          artist: '歌手',
          album: '专辑',
          sourceUri: 'content://song/notify',
          sourceType: MusicSourceType.local,
        );
        await store.save(
          track.copyWith(lastPlayedAt: DateTime.now(), lastPositionMs: 66000),
        );

        var opened = false;
        await controller.initialize();
        controller.setNotificationOpenedCallbackForTesting((_) async {
          opened = true;
        });
        await controller.playFromLibrary(track, const <MusicTrack>[track]);

        // 弹窗尚未处理，通知入口直接按上次位置续播。
        expect(controller.resumeRequestChanges.value, isNotNull);
        await controller.handleNotificationOpen();

        expect(playCalls.single['positionMs'], 66000);
        expect(controller.currentTrack?.trackKey, track.trackKey);
        expect(controller.resumeRequestChanges.value, isNull);
        expect(opened, isTrue);
      },
    );
  });
}

class _CountingMetadataResolver with MusicMetadataResolver {
  _CountingMetadataResolver({required this.onCall});

  final void Function() onCall;

  @override
  Future<MusicLyrics> lyrics({
    required String apiBaseUrl,
    required String remoteId,
    required String apiKey,
  }) async {
    onCall();
    return const MusicLyrics();
  }

  @override
  Future<String?> artworkUrl({
    required String apiBaseUrl,
    required String remoteId,
    required String apiKey,
  }) async {
    onCall();
    return null;
  }
}
