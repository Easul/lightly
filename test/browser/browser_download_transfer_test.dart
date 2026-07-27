import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_download_transfer.dart';

void main() {
  group('BrowserDownloadTransfer', () {
    test('retries a transient server error', () async {
      var attempts = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        attempts += 1;
        if (attempts == 1) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
        } else {
          request.response.contentLength = 3;
          request.response.add(<int>[1, 2, 3]);
        }
        await request.response.close();
      });
      final tempDirectory = await Directory.systemTemp.createTemp(
        'download_transfer_test_',
      );
      final outputFile = File('${tempDirectory.path}/archive.zip');
      final transfer = BrowserDownloadTransfer(
        client: HttpClient(),
        retryDelay: (_) => Duration.zero,
      );

      try {
        final result = await transfer.run(
          url: Uri.parse(
            'http://${server.address.host}:${server.port}/archive.zip',
          ),
          outputFile: outputFile,
          requestHeaders: const <String, String>{},
          initialTotalBytes: 0,
          onProgress: (_, _) async {},
          onRetry: (_, _) {},
          validateResponse: (_) {},
        );

        expect(attempts, 2);
        expect(result.bytesReceived, 3);
        expect(result.totalBytes, 3);
        expect(await outputFile.readAsBytes(), <int>[1, 2, 3]);
      } finally {
        await transfer.finish();
        await subscription.cancel();
        await server.close(force: true);
        await tempDirectory.delete(recursive: true);
      }
    });

    test(
      'retries a truncated response with a validated range request',
      () async {
        final payload = Uint8List.fromList(
          List<int>.generate(700000, (index) => index % 251),
        );
        const firstChunkLength = 360000;
        final requests = <String>[];
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((socket) {
          _readRequest(socket).then((request) async {
            requests.add(request);
            if (requests.length == 1) {
              socket.add(
                ascii.encode(
                  'HTTP/1.1 200 OK\r\n'
                  'Content-Length: ${payload.length}\r\n'
                  'ETag: "download-v1"\r\n'
                  'Connection: close\r\n\r\n',
                ),
              );
              socket.add(payload.sublist(0, firstChunkLength));
              await socket.flush();
              socket.destroy();
              return;
            }

            socket.add(
              ascii.encode(
                'HTTP/1.1 206 Partial Content\r\n'
                'Content-Length: ${payload.length - firstChunkLength}\r\n'
                'Content-Range: bytes $firstChunkLength-'
                '${payload.length - 1}/${payload.length}\r\n'
                'ETag: "download-v1"\r\n'
                'Connection: close\r\n\r\n',
              ),
            );
            socket.add(payload.sublist(firstChunkLength));
            await socket.flush();
            await socket.close();
          });
        });
        final tempDirectory = await Directory.systemTemp.createTemp(
          'download_transfer_test_',
        );
        final outputFile = File('${tempDirectory.path}/archive.zip');
        final transfer = BrowserDownloadTransfer(
          client: HttpClient(),
          retryDelay: (_) => Duration.zero,
          idleTimeout: const Duration(seconds: 2),
        );
        final retries = <String>[];

        try {
          final result = await transfer.run(
            url: Uri.parse(
              'http://${server.address.host}:${server.port}/archive.zip',
            ),
            outputFile: outputFile,
            requestHeaders: const <String, String>{},
            initialTotalBytes: payload.length,
            onProgress: (_, _) async {},
            onRetry: (retryNumber, maxRetries) {
              retries.add('$retryNumber/$maxRetries');
            },
            validateResponse: (_) {},
          );

          expect(result.bytesReceived, payload.length);
          expect(result.totalBytes, payload.length);
          expect(await outputFile.readAsBytes(), payload);
          expect(retries, <String>['1/3']);
          expect(requests, hasLength(2));
          expect(
            requests[1].toLowerCase(),
            contains('range: bytes=$firstChunkLength-'),
          );
          expect(
            requests[1].toLowerCase(),
            contains('accept-encoding: identity'),
          );
          expect(
            requests[1].toLowerCase(),
            contains('if-range: "download-v1"'),
          );
        } finally {
          await transfer.finish();
          await subscription.cancel();
          await server.close();
          await tempDirectory.delete(recursive: true);
        }
      },
    );

    test('rejects a mismatched content range without appending', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-4/10',
        );
        request.response.contentLength = 5;
        request.response.add(<int>[6, 7, 8, 9, 10]);
        await request.response.close();
      });
      final tempDirectory = await Directory.systemTemp.createTemp(
        'download_transfer_test_',
      );
      final outputFile = File('${tempDirectory.path}/archive.zip');
      await outputFile.writeAsBytes(<int>[1, 2, 3, 4, 5]);
      final transfer = BrowserDownloadTransfer(
        client: HttpClient(),
        maxAttempts: 1,
      );

      try {
        await expectLater(
          transfer.run(
            url: Uri.parse(
              'http://${server.address.host}:${server.port}/archive.zip',
            ),
            outputFile: outputFile,
            requestHeaders: const <String, String>{},
            initialTotalBytes: 10,
            onProgress: (_, _) async {},
            onRetry: (_, _) {},
            validateResponse: (_) {},
          ),
          throwsA(isA<BrowserDownloadProtocolException>()),
        );
        expect(await outputFile.readAsBytes(), <int>[1, 2, 3, 4, 5]);
      } finally {
        await transfer.finish();
        await subscription.cancel();
        await server.close(force: true);
        await tempDirectory.delete(recursive: true);
      }
    });
  });
}

Future<String> _readRequest(Socket socket) async {
  final completer = Completer<String>();
  final bytes = BytesBuilder(copy: false);
  late final StreamSubscription<List<int>> subscription;
  subscription = socket.listen(
    (chunk) {
      bytes.add(chunk);
      final request = ascii.decode(bytes.toBytes(), allowInvalid: true);
      if (request.contains('\r\n\r\n') && !completer.isCompleted) {
        completer.complete(request);
        subscription.pause();
      }
    },
    onError: completer.completeError,
    onDone: () {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Socket closed before request.'));
      }
    },
  );
  return completer.future;
}
