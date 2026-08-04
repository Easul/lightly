import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lightly/core/storage/shared_downloads_access.dart';
import 'package:lightly/features/music/domain/music_track.dart';
import 'package:lightly/features/music/infrastructure/music_download_service.dart';
import 'package:path/path.dart' as p;

class _FixedDownloadsAccess implements SharedDownloadsAccess {
  _FixedDownloadsAccess(this.directory);

  final Directory directory;

  @override
  Future<bool> hasFileAccessPermission() async => true;

  @override
  Future<bool> requestFileAccessPermission() async => true;

  @override
  Future<String?> getSharedDownloadsPath() async => directory.path;

  @override
  Future<Directory> resolveDirectory({
    bool preferSharedDownloads = true,
    bool requestSharedAccessIfNeeded = false,
    String androidFallbackFolderName = 'browser_downloads',
    String nonAndroidFallbackFolderName = 'downloads',
  }) async => directory;
}

void main() {
  group('MusicDownloadService file naming', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('music_dl_test');
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    MusicDownloadService buildService() {
      return MusicDownloadService(
        downloadsAccess: _FixedDownloadsAccess(tempDirectory),
        client: MockClient((request) async {
          return http.Response.bytes(
            utf8.encode('audio-bytes'),
            200,
            headers: <String, String>{'content-type': 'audio/mpeg'},
          );
        }),
      );
    }

    test('names files 歌手名-歌曲名', () async {
      const track = MusicTrack(
        trackKey: 'online:1',
        remoteId: '1',
        title: '歌曲名',
        artist: '歌手名',
        album: '专辑',
        sourceUri: 'https://cdn.test/a/1.mp3',
        sourceType: MusicSourceType.online,
      );

      final result = await buildService().download(
        track,
        preferSharedDownloads: true,
        requestSharedAccessIfNeeded: false,
      );

      expect(p.basename(result.localPath!), '歌手名-歌曲名.mp3');
      expect(await File(result.localPath!).exists(), isTrue);
    });

    test(
      'same artist+title from different remote ids lands in a distinct file',
      () async {
        final service = buildService();
        const first = MusicTrack(
          trackKey: 'online:1',
          remoteId: '1',
          title: '同名歌曲',
          artist: '歌手',
          album: '专辑',
          sourceUri: 'https://cdn.test/a/1.mp3',
          sourceType: MusicSourceType.online,
        );
        const second = MusicTrack(
          trackKey: 'online:2',
          remoteId: '2',
          title: '同名歌曲',
          artist: '歌手',
          album: '专辑',
          sourceUri: 'https://cdn.test/a/2.mp3',
          sourceType: MusicSourceType.online,
        );

        final firstResult = await service.download(
          first,
          preferSharedDownloads: true,
          requestSharedAccessIfNeeded: false,
        );
        final secondResult = await service.download(
          second,
          preferSharedDownloads: true,
          requestSharedAccessIfNeeded: false,
        );

        expect(p.basename(firstResult.localPath!), '歌手-同名歌曲.mp3');
        expect(secondResult.localPath, isNot(firstResult.localPath));
        expect(p.basename(secondResult.localPath!), startsWith('歌手-同名歌曲-'));
        expect(p.basename(secondResult.localPath!), endsWith('.mp3'));
        expect(await File(secondResult.localPath!).exists(), isTrue);

        // The md5 discriminator is stable per song: re-downloading the same
        // colliding id overwrites the same file instead of accumulating.
        final redownload = await service.download(
          second,
          preferSharedDownloads: true,
          requestSharedAccessIfNeeded: false,
        );
        expect(redownload.localPath, secondResult.localPath);
      },
    );

    test('re-downloading an existing id overwrites the plain file', () async {
      final service = buildService();
      const track = MusicTrack(
        trackKey: 'online:9',
        remoteId: '9',
        title: '归来',
        artist: '歌手',
        album: '专辑',
        sourceUri: 'https://cdn.test/a/9.mp3',
        sourceType: MusicSourceType.online,
      );

      final first = await service.download(
        track,
        preferSharedDownloads: true,
        requestSharedAccessIfNeeded: false,
      );
      final again = await service.download(
        track,
        preferSharedDownloads: true,
        requestSharedAccessIfNeeded: false,
      );

      expect(again.localPath, first.localPath);
      expect(p.basename(again.localPath!), '歌手-归来.mp3');
    });
  });
}
