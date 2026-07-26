import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/core/logging/runtime_logger.dart';
import 'package:lightly/features/proxy/infrastructure/proxy_core_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.proxy.core/proxy');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'records platform failures through the injected runtime logger',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'native_init_failed');
          });
      final logger = _RecordingRuntimeLogger();
      final service = ProxyCoreService(runtimeLogger: logger);

      final result = await service.init(logLevel: 'warn');

      expect(result, -1);
      expect(logger.messages, <String>[
        '[ProxyCore] Native proxy initialization failed',
      ]);
      expect(logger.metadata.single, <String, Object?>{
        'code': 'native_init_failed',
        'logLevel': 'warn',
      });
    },
  );
}

class _RecordingRuntimeLogger implements RuntimeLogger {
  final List<String> messages = <String>[];
  final List<Map<String, Object?>?> metadata = <Map<String, Object?>?>[];

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
    this.metadata.add(metadata);
  }

  @override
  Future<void> logFlutterError(FlutterErrorDetails details) async {}

  @override
  Future<void> logUnhandledError(Object error, StackTrace stackTrace) async {}
}
