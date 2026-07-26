import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import '../../../core/logging/runtime_logger.dart';
import '../domain/proxy_core_config.dart';

class ProxyCoreService {
  ProxyCoreService({RuntimeLogger? runtimeLogger})
    : _runtimeLogger = runtimeLogger;

  static const MethodChannel _channel = MethodChannel('com.proxy.core/proxy');

  bool _isRunning = false;
  String _listenAddr = '127.0.0.1:23333';
  RuntimeLogger? _runtimeLogger;

  bool get isRunning => _isRunning;
  String get listenAddr => _listenAddr;

  set runtimeLogger(RuntimeLogger? value) {
    _runtimeLogger = value;
  }

  Future<int> init({String logLevel = 'info'}) async {
    try {
      final result = await _channel.invokeMethod<int>('nativeInit', {
        'logLevel': logLevel,
      });
      return result ?? -1;
    } on PlatformException catch (e, stackTrace) {
      _recordRuntimeLog(
        'Native proxy initialization failed',
        error: e,
        stackTrace: stackTrace,
        metadata: <String, Object?>{'code': e.code, 'logLevel': logLevel},
      );
      return -1;
    }
  }

  Future<int> start({
    String listenAddr = '127.0.0.1:23333',
    VlessConfig? vlessConfig,
    Hysteria2Config? hysteria2Config,
  }) async {
    if (_isRunning) {
      return 0;
    }

    final config = hysteria2Config?.toJson() ?? vlessConfig?.toJson() ?? '{}';

    try {
      final result = await _channel.invokeMethod<int>('nativeStart', {
        'listenAddr': listenAddr,
        'config': config,
      });

      if (result == 0) {
        _isRunning = true;
        _listenAddr = listenAddr;
      }

      return result ?? -1;
    } on PlatformException catch (e, stackTrace) {
      _recordRuntimeLog(
        'Native proxy start failed',
        error: e,
        stackTrace: stackTrace,
        metadata: <String, Object?>{
          'code': e.code,
          'listenAddr': listenAddr,
          'protocol': hysteria2Config != null ? 'hysteria2' : 'vless',
        },
      );
      return -1;
    }
  }

  Future<int> stop() async {
    if (!_isRunning) {
      return 0;
    }

    try {
      final result = await _channel.invokeMethod<int>('nativeStop');
      if (result == 0) {
        _isRunning = false;
      }
      return result ?? -1;
    } on PlatformException catch (e, stackTrace) {
      _recordRuntimeLog(
        'Native proxy stop failed',
        error: e,
        stackTrace: stackTrace,
        metadata: <String, Object?>{'code': e.code},
      );
      return -1;
    }
  }

  Future<int> startWithVless({
    String logLevel = 'info',
    String listenAddr = '127.0.0.1:23333',
    required VlessConfig vlessConfig,
  }) async {
    final initResult = await init(logLevel: logLevel);
    if (initResult != 0) {
      return initResult;
    }
    return start(listenAddr: listenAddr, vlessConfig: vlessConfig);
  }

  Future<int> startWithHysteria2({
    String logLevel = 'info',
    String listenAddr = '127.0.0.1:23333',
    required Hysteria2Config hysteria2Config,
  }) async {
    final initResult = await init(logLevel: logLevel);
    if (initResult != 0) {
      return initResult;
    }
    return start(listenAddr: listenAddr, hysteria2Config: hysteria2Config);
  }

  Future<void> dispose() async {
    await stop();
  }

  void _recordRuntimeLog(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? metadata,
  }) {
    developer.log(
      message,
      name: 'ProxyCore',
      error: error,
      stackTrace: stackTrace,
    );
    final runtimeLogger = _runtimeLogger;
    if (runtimeLogger == null) {
      return;
    }
    unawaited(
      runtimeLogger
          .log(
            '[ProxyCore] $message',
            error: error,
            stackTrace: stackTrace,
            metadata: metadata,
          )
          .catchError((_) {}),
    );
  }
}
