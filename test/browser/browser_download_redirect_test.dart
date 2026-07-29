import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_download_transfer.dart';

void main() {
  group('BrowserDownloadTransfer redirects', () {
    test('preserves request headers across a same-origin redirect', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? receivedCookie;
      String? receivedAuthorization;
      String? receivedReferer;
      final subscription = server.listen((request) async {
        if (request.uri.path == '/start') {
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, '/files/archive.zip');
        } else {
          receivedCookie = request.headers.value(HttpHeaders.cookieHeader);
          receivedAuthorization = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          receivedReferer = request.headers.value(HttpHeaders.refererHeader);
          request.response
            ..contentLength = 3
            ..add(<int>[1, 2, 3]);
        }
        await request.response.close();
      });
      final tempDirectory = await Directory.systemTemp.createTemp(
        'download_redirect_test_',
      );
      final outputFile = File('${tempDirectory.path}/archive.zip');
      final transfer = BrowserDownloadTransfer(client: HttpClient());
      Uri? finalUrl;

      try {
        await transfer.run(
          url: Uri.parse('http://${server.address.host}:${server.port}/start'),
          outputFile: outputFile,
          requestHeaders: const <String, String>{
            HttpHeaders.cookieHeader: 'session=secret',
            HttpHeaders.authorizationHeader: 'Bearer token',
            HttpHeaders.refererHeader: 'https://example.com/page',
          },
          initialTotalBytes: 0,
          onProgress: (_, _) async {},
          onRetry: (_, _) {},
          validateResponse: (_) {},
          resolveOutputFile: (response, file, resolvedUrl) async {
            finalUrl = resolvedUrl;
            return file;
          },
        );

        expect(receivedCookie, 'session=secret');
        expect(receivedAuthorization, 'Bearer token');
        expect(receivedReferer, 'https://example.com/page');
        expect(finalUrl?.path, '/files/archive.zip');
        expect(await outputFile.readAsBytes(), <int>[1, 2, 3]);
      } finally {
        await transfer.finish();
        await subscription.cancel();
        await server.close(force: true);
        await tempDirectory.delete(recursive: true);
      }
    });

    test('strips sensitive headers when redirect origin changes', () async {
      final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirector = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final receivedHeaders = <String, String?>{};
      final targetSubscription = target.listen((request) async {
        for (final name in <String>[
          HttpHeaders.cookieHeader,
          HttpHeaders.authorizationHeader,
          HttpHeaders.refererHeader,
          'proxy-authorization',
          HttpHeaders.userAgentHeader,
          'x-download-test',
        ]) {
          receivedHeaders[name] = request.headers.value(name);
        }
        request.response
          ..contentLength = 1
          ..add(<int>[7]);
        await request.response.close();
      });
      final redirectSubscription = redirector.listen((request) async {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(
            HttpHeaders.locationHeader,
            'http://${target.address.host}:${target.port}/file.bin',
          );
        await request.response.close();
      });
      final tempDirectory = await Directory.systemTemp.createTemp(
        'download_redirect_test_',
      );
      final outputFile = File('${tempDirectory.path}/file.bin');
      final transfer = BrowserDownloadTransfer(client: HttpClient());

      try {
        await transfer.run(
          url: Uri.parse('http://localhost:${redirector.port}/start'),
          outputFile: outputFile,
          requestHeaders: const <String, String>{
            HttpHeaders.cookieHeader: 'session=secret',
            HttpHeaders.authorizationHeader: 'Bearer token',
            HttpHeaders.refererHeader: 'https://example.com/page',
            'proxy-authorization': 'Basic secret',
            HttpHeaders.userAgentHeader: 'Lightly Test',
            'x-download-test': 'preserved',
          },
          initialTotalBytes: 0,
          onProgress: (_, _) async {},
          onRetry: (_, _) {},
          validateResponse: (_) {},
        );

        expect(receivedHeaders[HttpHeaders.cookieHeader], isNull);
        expect(receivedHeaders[HttpHeaders.authorizationHeader], isNull);
        expect(receivedHeaders[HttpHeaders.refererHeader], isNull);
        expect(receivedHeaders['proxy-authorization'], isNull);
        expect(receivedHeaders[HttpHeaders.userAgentHeader], 'Lightly Test');
        expect(receivedHeaders['x-download-test'], 'preserved');
      } finally {
        await transfer.finish();
        await redirectSubscription.cancel();
        await targetSubscription.cancel();
        await redirector.close(force: true);
        await target.close(force: true);
        await tempDirectory.delete(recursive: true);
      }
    });

    test('rejects a redirect to a non-http scheme', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, 'file:///tmp/archive.zip');
        await request.response.close();
      });
      final tempDirectory = await Directory.systemTemp.createTemp(
        'download_redirect_test_',
      );
      final transfer = BrowserDownloadTransfer(client: HttpClient());

      try {
        await expectLater(
          transfer.run(
            url: Uri.parse(
              'http://${server.address.host}:${server.port}/start',
            ),
            outputFile: File('${tempDirectory.path}/archive.zip'),
            requestHeaders: const <String, String>{},
            initialTotalBytes: 0,
            onProgress: (_, _) async {},
            onRetry: (_, _) {},
            validateResponse: (_) {},
          ),
          throwsA(isA<BrowserDownloadProtocolException>()),
        );
      } finally {
        await transfer.finish();
        await subscription.cancel();
        await server.close(force: true);
        await tempDirectory.delete(recursive: true);
      }
    });

    test('rejects downloads that exceed the redirect limit', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requestCount = 0;
      final subscription = server.listen((request) async {
        requestCount++;
        final hop = int.parse(request.uri.pathSegments.single);
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/${hop + 1}');
        await request.response.close();
      });
      final tempDirectory = await Directory.systemTemp.createTemp(
        'download_redirect_test_',
      );
      final transfer = BrowserDownloadTransfer(client: HttpClient());

      try {
        await expectLater(
          transfer.run(
            url: Uri.parse('http://${server.address.host}:${server.port}/0'),
            outputFile: File('${tempDirectory.path}/archive.zip'),
            requestHeaders: const <String, String>{},
            initialTotalBytes: 0,
            onProgress: (_, _) async {},
            onRetry: (_, _) {},
            validateResponse: (_) {},
          ),
          throwsA(isA<BrowserDownloadProtocolException>()),
        );
        expect(requestCount, 6);
      } finally {
        await transfer.finish();
        await subscription.cancel();
        await server.close(force: true);
        await tempDirectory.delete(recursive: true);
      }
    });
  });
}
