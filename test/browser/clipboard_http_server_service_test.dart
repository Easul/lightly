import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/core/logging/runtime_logger.dart';
import 'package:lightly/features/local_sharing/clipboard/clipboard_http_server_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ClipboardHttpServerService service;
  late _FakeRuntimeLogger runtimeLogger;

  setUp(() async {
    HttpOverrides.global = null;
    runtimeLogger = _FakeRuntimeLogger();
    service = ClipboardHttpServerService(runtimeLogger: runtimeLogger);
    await service.stop();
  });

  tearDown(() => service.stop());

  test('records unexpected request failures through RuntimeLogger', () async {
    await service.start();
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('${service.localUrl}/save'),
      );
      request.add(<int>[0xff]);
      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(runtimeLogger.messages, <String>[
        '[ClipboardHttpServer] Request handling failed',
      ]);
      expect(runtimeLogger.metadata.single, <String, Object?>{
        'method': 'POST',
        'path': '/save',
      });
    } finally {
      client.close(force: true);
    }
  });
}

class _FakeRuntimeLogger implements RuntimeLogger {
  final List<String> messages = <String>[];
  final List<Map<String, Object?>> metadata = <Map<String, Object?>>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> log(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? metadata,
  }) async {
    messages.add(message);
    this.metadata.add(metadata ?? const <String, Object?>{});
  }

  @override
  Future<void> logFlutterError(FlutterErrorDetails details) async {}

  @override
  Future<void> logUnhandledError(Object error, StackTrace stackTrace) async {}
}
