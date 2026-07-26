import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/models/browser_download_record.dart';
import 'package:lightly/browser/services/browser_download_service.dart';
import 'package:lightly/browser/services/browser_download_store.dart';
import 'package:lightly/features/proxy/infrastructure/proxy_service.dart';

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

    test('rejects html response for a binary download filename', () {
      expect(
        BrowserDownloadService.isUnexpectedHtmlResponse(
          fileName: 'application.apk',
          mimeType: 'text/html',
        ),
        isTrue,
      );
      expect(
        BrowserDownloadService.isUnexpectedHtmlResponse(
          fileName: 'application.apk',
          mimeType: 'application/vnd.android.package-archive',
        ),
        isFalse,
      );
    });

    test('allows an intentional html file download', () {
      expect(
        BrowserDownloadService.isUnexpectedHtmlResponse(
          fileName: 'offline-page.html',
          mimeType: 'text/html',
        ),
        isFalse,
      );
    });

    test('sends webview headers and rejects redirected html content', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      late HttpHeaders receivedHeaders;
      server.listen((request) async {
        receivedHeaders = request.headers;
        request.response.headers.contentType = ContentType.html;
        request.response.write('<html>login required</html>');
        await request.response.close();
      });
      final tempDir = await Directory.systemTemp.createTemp('download_test_');
      final savedPath = '${tempDir.path}/application.apk';
      final store = _RecordingDownloadStore();
      final statuses = <String>[];
      final record = BrowserDownloadRecord(
        id: 1,
        url: 'http://${server.address.host}:${server.port}/application.apk',
        fileName: 'application.apk',
        status: 'pending',
        savedPath: savedPath,
        totalBytes: 0,
        bytesReceived: 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      try {
        await service.startDownload(
          url: record.url,
          record: record,
          savedPath: savedPath,
          proxyService: ProxyService(),
          settings: BrowserSettings.defaults(),
          downloadStore: store,
          onStatus: statuses.add,
          requestHeaders: const <String, String>{
            HttpHeaders.userAgentHeader: 'WebView UA',
            HttpHeaders.cookieHeader: 'session=secret',
            HttpHeaders.refererHeader: 'https://gofile.io/d/content-id',
          },
        );

        expect(
          receivedHeaders.value(HttpHeaders.userAgentHeader),
          'WebView UA',
        );
        expect(
          receivedHeaders.value(HttpHeaders.cookieHeader),
          'session=secret',
        );
        expect(
          receivedHeaders.value(HttpHeaders.refererHeader),
          'https://gofile.io/d/content-id',
        );
        expect(store.updates.last.status, 'failed');
        expect(statuses.last, contains('服务器返回的是网页'));
        expect(await File(savedPath).exists(), isFalse);
      } finally {
        await server.close(force: true);
        await tempDir.delete(recursive: true);
      }
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

class _RecordingDownloadStore extends BrowserDownloadStore {
  final List<BrowserDownloadRecord> updates = <BrowserDownloadRecord>[];

  @override
  Future<void> update(BrowserDownloadRecord record) async {
    updates.add(record);
  }
}
