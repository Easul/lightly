import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_download_file_name_resolver.dart';

void main() {
  group('BrowserDownloadFileNameResolver', () {
    late BrowserDownloadFileNameResolver resolver;

    setUp(() {
      resolver = BrowserDownloadFileNameResolver(
        now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    });

    test('prefers RFC 5987 content disposition filename', () {
      expect(
        resolver.resolve(
          suggestedFileName: 'download.bin',
          contentDisposition:
              "attachment; filename=fallback.zip; "
              "filename*=UTF-8''%E6%B5%8B%E8%AF%95.zip",
          url: Uri.parse('https://example.com/download'),
          mimeType: 'application/octet-stream',
        ),
        '测试.zip',
      );
    });

    test('reads case-insensitive filename query parameter', () {
      expect(
        resolver.resolve(
          url: Uri.parse(
            'https://zip.example.com/hash.bin'
            '?fileName=click-android-arm64-v8a.apk.zip&token=secret',
          ),
        ),
        'click-android-arm64-v8a.apk.zip',
      );
    });

    test('reads response content disposition query parameter', () {
      expect(
        resolver.resolve(
          url: Uri.parse(
            'https://storage.example.com/object'
            '?response-content-disposition='
            'attachment%3B%20filename%3Darchive.zip',
          ),
        ),
        'archive.zip',
      );
    });

    test('ignores toggle and ambiguous query values', () {
      expect(
        resolver.resolve(
          url: Uri.parse(
            'https://example.com/archive.zip?download=1&name=profile',
          ),
        ),
        'archive.zip',
      );
    });

    test('uses MIME extension for a generic binary name', () {
      expect(
        resolver.resolve(
          suggestedFileName: 'archive.bin',
          url: Uri.parse('https://example.com/download'),
          mimeType: 'application/zip',
        ),
        'archive.zip',
      );
    });

    test('keeps the original timestamped binary fallback', () {
      expect(
        resolver.resolve(
          url: Uri.parse('https://example.com/download/'),
          mimeType: 'application/octet-stream',
        ),
        'download_1700000000000.bin',
      );
    });

    test('strips path components from untrusted names', () {
      expect(
        resolver.fileNameFromContentDisposition(
          'attachment; filename="../../private/archive.zip"',
        ),
        'archive.zip',
      );
    });

    test('falls back when an extended filename is malformed', () {
      expect(
        resolver.fileNameFromContentDisposition(
          "attachment; filename=fallback.zip; filename*=UTF-8''%ZZ",
        ),
        'fallback.zip',
      );
    });
  });
}
