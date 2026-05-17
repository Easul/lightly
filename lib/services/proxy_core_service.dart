import 'dart:convert';

import 'package:flutter/services.dart';

class ProxyCoreService {
  static const MethodChannel _channel = MethodChannel('com.proxy.core/proxy');

  bool _isRunning = false;
  String _listenAddr = '127.0.0.1:23333';

  bool get isRunning => _isRunning;
  String get listenAddr => _listenAddr;

  Future<int> init({String logLevel = 'info'}) async {
    try {
      final result = await _channel.invokeMethod<int>('nativeInit', {
        'logLevel': logLevel,
      });
      return result ?? -1;
    } on PlatformException catch (e) {
      print('ProxyCore init error: ${e.message}');
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
    } on PlatformException catch (e) {
      print('ProxyCore start error: ${e.message}');
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
    } on PlatformException catch (e) {
      print('ProxyCore stop error: ${e.message}');
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
}

class VlessConfig {
  final String uuid;
  final String serverAddr;
  final int serverPort;
  final String security;
  final String? host;
  final String? sni;
  final String path;
  final bool tlsInsecure;

  VlessConfig({
    required this.uuid,
    required this.serverAddr,
    this.serverPort = 443,
    this.security = 'tls',
    this.host,
    this.sni,
    this.path = '/',
    this.tlsInsecure = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'vless': {
        'uuid': uuid,
        'server_addr': serverAddr,
        'server_port': serverPort,
        'security': security,
        'host': host,
        'sni': sni,
        'path': path,
        'tls_insecure': tlsInsecure,
      },
    };
  }

  String toJson() => jsonEncode(toMap());
}

class Hysteria2Config {
  final String serverAddr;
  final int serverPort;
  final String password;
  final String? sni;
  final String? obfs;
  final String? obfsPassword;
  final bool tlsInsecure;

  Hysteria2Config({
    required this.serverAddr,
    this.serverPort = 443,
    required this.password,
    this.sni,
    this.obfs,
    this.obfsPassword,
    this.tlsInsecure = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'hysteria2': {
        'server_addr': serverAddr,
        'server_port': serverPort,
        'password': password,
        'sni': sni,
        'obfs': obfs,
        'obfs_password': obfsPassword,
        'tls_insecure': tlsInsecure,
      },
    };
  }

  String toJson() => jsonEncode(toMap());
}
