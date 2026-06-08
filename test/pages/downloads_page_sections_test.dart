import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/models/browser_download_record.dart';
import 'package:lightly/pages/downloads_page_sections.dart';

void main() {
  group('isPlayableDownloadedVideo', () {
    test('allows completed video records with a saved path', () {
      final record = BrowserDownloadRecord(
        url: 'https://example.com/video',
        fileName: 'clip.mp4',
        status: 'completed',
        savedPath: '/storage/emulated/0/Download/clip.mp4',
        totalBytes: 10,
        bytesReceived: 10,
        createdAt: DateTime(2026),
      );

      expect(isPlayableDownloadedVideo(record), isTrue);
    });

    test('rejects unfinished, missing-path, and non-video records', () {
      final base = BrowserDownloadRecord(
        url: 'https://example.com/file',
        fileName: 'clip.mp4',
        status: 'completed',
        savedPath: '/storage/emulated/0/Download/clip.mp4',
        totalBytes: 10,
        bytesReceived: 10,
        createdAt: DateTime(2026),
      );

      expect(
        isPlayableDownloadedVideo(base.copyWith(status: 'downloading')),
        isFalse,
      );
      expect(
        isPlayableDownloadedVideo(base.copyWith(clearSavedPath: true)),
        isFalse,
      );
      expect(
        isPlayableDownloadedVideo(
          base.copyWith(
            fileName: 'archive.zip',
            savedPath: '/storage/emulated/0/Download/archive.zip',
          ),
        ),
        isFalse,
      );
    });
  });
}
