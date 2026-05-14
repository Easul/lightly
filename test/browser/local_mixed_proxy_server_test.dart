import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/local_mixed_proxy_server.dart';
import 'package:lightly/browser/vless_client.dart';

void main() {
  group('LocalMixedProxyServer', () {
    late LocalMixedProxyServer server;

    final config = VlessConfig(
      uuid: '86c50e3a-5b87-49dd-bd20-03c7f2735e40',
      host: 'example.com',
      port: 443,
    );

    setUp(() {
      server = LocalMixedProxyServer();
    });

    tearDown(() async {
      await server.stop();
    });

    test('binds to dynamic localhost port', () async {
      await server.start(config);

      expect(server.isRunning, isTrue);
      expect(server.boundPort, isNotNull);
      expect(server.boundPort, greaterThan(0));
      expect(server.boundPort, isNot(10808));
    });

    test('does not depend on port 10808 being free', () async {
      final blocker = await ServerSocket.bind(
        LocalMixedProxyServer.localHost,
        10808,
      );
      addTearDown(() => blocker.close());

      await server.start(config);

      expect(server.isRunning, isTrue);
      expect(server.boundPort, isNotNull);
      expect(server.boundPort, isNot(10808));
    });

    test('binds to preferred port when provided', () async {
      await server.start(config, preferredPort: 19090);

      expect(server.isRunning, isTrue);
      expect(server.boundPort, 19090);
    });

    test('accepts socks5 no-auth negotiation', () async {
      await server.start(config);
      final socket = await Socket.connect(
        LocalMixedProxyServer.localHost,
        server.boundPort!,
      );
      addTearDown(() => socket.destroy());

      socket.add(const [0x05, 0x01, 0x00]);
      await socket.flush();

      final completer = Completer<List<int>?>();
      late StreamSubscription<List<int>> sub;
      sub = socket.listen(
        (data) {
          if (!completer.isCompleted) completer.complete(data);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(null);
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(null);
        },
        cancelOnError: true,
      );

      final result = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      await sub.cancel();

      expect(result, [0x05, 0x00]);
    });

    test('rejects socks5 auth methods when no-auth is unavailable', () async {
      await server.start(config);
      final socket = await Socket.connect(
        LocalMixedProxyServer.localHost,
        server.boundPort!,
      );
      addTearDown(() => socket.destroy());

      socket.add(const [0x05, 0x01, 0x01]);
      await socket.flush();

      final completer = Completer<List<int>?>();
      late StreamSubscription<List<int>> sub;
      sub = socket.listen(
        (data) {
          if (!completer.isCompleted) completer.complete(data);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(null);
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(null);
        },
        cancelOnError: true,
      );

      final result = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      await sub.cancel();

      expect(result, [0x05, 0xff]);
    });

    test('accepts socks5 username-password negotiation', () async {
      await server.start(config);
      final socket = await Socket.connect(
        LocalMixedProxyServer.localHost,
        server.boundPort!,
      );
      addTearDown(() => socket.destroy());

      final responses = <List<int>>[];
      final completer = Completer<void>();
      late StreamSubscription<List<int>> sub;
      sub = socket.listen((data) {
        responses.add(data);
        if (responses.length >= 2 && !completer.isCompleted) {
          completer.complete();
        }
      });

      socket.add(const [0x05, 0x01, 0x02]);
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final greetingReply = responses.isNotEmpty ? responses.first : null;
      expect(greetingReply, [0x05, 0x02]);

      socket.add(const [0x01, 0x00, 0x00]);
      await socket.flush();

      await completer.future.timeout(const Duration(seconds: 2));
      final authReply = responses[1];
      await sub.cancel();
      expect(authReply, [0x01, 0x00]);
    });

    test('rewrites absolute-form HTTP request line to origin-form', () {
      expect(
        LocalMixedProxyServer.normalizeHttpProxyRequestLineForOrigin(
          'GET http://192.168.1.10/files/test.zip?download=1 HTTP/1.1',
        ),
        'GET /files/test.zip?download=1 HTTP/1.1',
      );
    });

    test('keeps origin-form HTTP request line unchanged', () {
      expect(
        LocalMixedProxyServer.normalizeHttpProxyRequestLineForOrigin(
          'GET /files/test.zip HTTP/1.1',
        ),
        'GET /files/test.zip HTTP/1.1',
      );
    });
  });
}
