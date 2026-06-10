import 'package:flutter/material.dart';
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

  group('DownloadRecordCard', () {
    testWidgets('long press exposes copy link action', (tester) async {
      final record = BrowserDownloadRecord(
        id: 1,
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        status: 'completed',
        savedPath: '/storage/emulated/0/Download/file.zip',
        totalBytes: 10,
        bytesReceived: 10,
        createdAt: DateTime(2026),
      );
      BrowserDownloadRecord? copied;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadRecordCard(
              record: record,
              onPause: (_) {},
              onResume: (_) {},
              onInstall: (_) {},
              onPlayVideo: (_) {},
              onDelete: (_) {},
              onCopyLink: (record) => copied = record,
            ),
          ),
        ),
      );

      await tester.longPress(find.text('file.zip'));
      await tester.pumpAndSettle();
      expect(find.text('复制链接'), findsOneWidget);

      await tester.tap(find.text('复制链接'));
      await tester.pumpAndSettle();
      expect(copied, same(record));
    });

    testWidgets('completed file card stays compact', (tester) async {
      final record = BrowserDownloadRecord(
        id: 1,
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        status: 'completed',
        savedPath: '/storage/emulated/0/Download/file.zip',
        totalBytes: 2048,
        bytesReceived: 2048,
        createdAt: DateTime(2026),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: DownloadRecordCard(
                record: record,
                onPause: (_) {},
                onResume: (_) {},
                onInstall: (_) {},
                onPlayVideo: (_) {},
                onDelete: (_) {},
                onCopyLink: (_) {},
              ),
            ),
          ),
        ),
      );

      final height = tester.getSize(find.byType(DownloadRecordCard)).height;
      expect(height, lessThanOrEqualTo(92));
    });
  });
}
