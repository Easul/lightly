import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lightly/browser/data/app_database.dart';
import 'package:lightly/browser/data/app_database_adapter.dart';
import 'package:lightly/features/music/domain/music_lyric.dart';
import 'package:lightly/features/music/domain/music_track.dart';
import 'package:lightly/features/music/infrastructure/music_api_client.dart';
import 'package:lightly/features/music/infrastructure/music_library_store.dart';
import 'package:lightly/features/music/infrastructure/music_settings_store.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
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
      final client = MusicApiClient(
        client: MockClient((request) async {
          requestedUri = request.url;
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
      expect(requestedUri.queryParameters['limit'], '10');
      expect(requestedUri.queryParameters['offset'], '10');
      expect(requestedUri.queryParameters['keyword'], '海底');
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
        ),
      );

      final settings = await store.load();
      expect(settings.apiBaseUrl, 'https://music.test/api/');
      expect(settings.apiKey, 'manual-key');
      expect(settings.quality, 'lossless');
      expect(settings.notificationEnabled, isFalse);
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
      },
    );
  });
}
