import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_download_service.dart';

void main() {
  group('BrowserDownloadService', () {
    late BrowserDownloadService service;

    setUp(() {
      service = BrowserDownloadService(
        now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    });

    test('resolveFileName prefers suggested filename', () {
      final request = DownloadStartRequest(
        url: WebUri('https://example.com/archive.bin'),
        contentLength: 128,
        suggestedFilename: 'report?.pdf',
        contentDisposition: 'attachment; filename="ignored.txt"',
      );

      expect(service.resolveFileName(request), 'report_.pdf');
    });

    test('resolveFileName falls back to content disposition filename', () {
      final request = DownloadStartRequest(
        url: WebUri('https://example.com/archive.bin'),
        contentLength: 128,
        contentDisposition: 'attachment; filename="export:2026.csv"',
      );

      expect(service.resolveFileName(request), 'export_2026.csv');
    });

    test('resolveFileName decodes utf8 content disposition filename', () {
      final request = DownloadStartRequest(
        url: WebUri('https://example.com/archive.bin'),
        contentLength: 128,
        contentDisposition:
            "attachment; filename*=UTF-8''%E6%B5%8B%E8%AF%95.zip",
      );

      expect(service.resolveFileName(request), '测试.zip');
    });

    test('resolveFileName falls back to decoded url path segment', () {
      final request = DownloadStartRequest(
        url: WebUri('https://example.com/files/hello%20world%3F.txt'),
        contentLength: 128,
      );

      expect(service.resolveFileName(request), 'hello world_.txt');
    });

    test('resolveFileName uses generated fallback when no name exists', () {
      final request = DownloadStartRequest(
        url: WebUri('https://example.com/download/'),
        contentLength: 128,
      );

      expect(service.resolveFileName(request), 'download_1700000000000.bin');
    });

    test('resolveFileNameFromUrl uses decoded url path segment', () {
      expect(
        service.resolveFileNameFromUrl(
          'https://example.com/files/hello%20world%3F.txt?download=1',
        ),
        'hello world_.txt',
      );
    });

    test(
      'resolveFileNameFromUrl uses generated fallback when path is empty',
      () {
        expect(
          service.resolveFileNameFromUrl('https://example.com/download/'),
          'download_1700000000000.bin',
        );
      },
    );

    test('sanitizeFileName replaces invalid path characters', () {
      expect(
        service.sanitizeFileName(r' a\b/c:d*e?f"g<h>i| '),
        'a_b_c_d_e_f_g_h_i_',
      );
    });

    test('sanitizeFileName uses generated fallback for blank names', () {
      expect(service.sanitizeFileName('   '), 'download_1700000000000.bin');
    });

    test('cancelDownload removes partial file when requested', () async {
      final tempDir = await Directory.systemTemp.createTemp('download_test_');
      final partialFile = File('${tempDir.path}/partial.bin');
      await partialFile.writeAsString('partial');

      await service.cancelDownload(
        123,
        savedPath: partialFile.path,
        deletePartialFile: true,
      );

      expect(await partialFile.exists(), isFalse);
      await tempDir.delete(recursive: true);
    });
  });
}
