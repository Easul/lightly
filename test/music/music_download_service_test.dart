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

    test(
      'same-titled songs from different remote ids land in distinct files',
      () async {
        final service = MusicDownloadService(
          downloadsAccess: _FixedDownloadsAccess(tempDirectory),
          client: MockClient((request) async {
            return http.Response.bytes(
              utf8.encode('audio-bytes'),
              200,
              headers: <String, String>{'content-type': 'audio/mpeg'},
            );
          }),
        );
        const first = MusicTrack(
          trackKey: 'online:1',
          remoteId: '1',
          title: '同名歌曲',
          artist: '歌手甲',
          album: '专辑',
          sourceUri: 'https://cdn.test/a/1.mp3',
          sourceType: MusicSourceType.online,
        );
        const second = MusicTrack(
          trackKey: 'online:2',
          remoteId: '2',
          title: '同名歌曲',
          artist: '歌手乙',
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

        expect(firstResult.localPath, isNot(secondResult.localPath));
        expect(p.basename(firstResult.localPath!), startsWith('同名歌曲-'));
        expect(p.basename(firstResult.localPath!), endsWith('.mp3'));
        expect(await File(firstResult.localPath!).exists(), isTrue);
        expect(await File(secondResult.localPath!).exists(), isTrue);

        // The discriminator is stable per song: re-downloading the same id
        // overwrites the same file instead of accumulating copies.
        final redownload = await service.download(
          first,
          preferSharedDownloads: true,
          requestSharedAccessIfNeeded: false,
        );
        expect(redownload.localPath, firstResult.localPath);
      },
    );
  });
}
