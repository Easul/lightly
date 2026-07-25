import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/services.dart';
import '../models/easytier_config.dart';
import 'app_log_service.dart';
import 'easytier_runtime.dart';

class EasyTierService implements EasyTierRuntime {
  static const MethodChannel _channel = MethodChannel('easytier_vpn');
  static const int noTunSocksPort = 11080;

  static final EasyTierService _instance = EasyTierService._internal();
  factory EasyTierService() => _instance;
  EasyTierService._internal();

  bool _isRunning = false;
  String? _lastError;
  String? _configString;
  String? _currentInstanceName;
  String? _lastRawNetworkInfo;
  bool _usesAndroidVpn = true;
  int? _activeNoTunSocksPort;

  @override
  bool get isRunning => _isRunning;
  String? get lastError => _lastError;
  String? get configString => _configString;
  String? get currentInstanceName => _currentInstanceName;
  String? get lastRawNetworkInfo => _lastRawNetworkInfo;
  bool get usesAndroidVpn => _usesAndroidVpn;
  @override
  bool get isNoTunMode => _isRunning && !_usesAndroidVpn;
  int? get activeNoTunSocksPort => isNoTunMode ? _activeNoTunSocksPort : null;

  Future<bool> parseConfig(String config) async {
    try {
      developer.log('Parsing EasyTier config', name: 'EasyTier');
      final result = await _channel.invokeMethod<bool>('parseConfig', {
        'config': config,
      });
      developer.log('Config parse result: $result', name: 'EasyTier');
      return result ?? false;
    } on PlatformException catch (e, stackTrace) {
      _lastError = e.message;
      recordRuntimeLog(
        'EasyTier',
        'Configuration parsing failed',
        error: e,
        stackTrace: stackTrace,
        metadata: <String, Object?>{'code': e.code},
      );
      return false;
    }
  }

  Future<bool> checkVpnPermission() async {
    try {
      developer.log('Checking VPN permission', name: 'EasyTier');
      final hasPermission = await _channel.invokeMethod<bool>(
        'checkVpnPermission',
      );
      developer.log(
        'VPN permission check result: $hasPermission',
        name: 'EasyTier',
      );
      return hasPermission ?? false;
    } on PlatformException catch (e, stackTrace) {
      recordRuntimeLog(
        'EasyTier',
        'VPN permission check failed',
        error: e,
        stackTrace: stackTrace,
        metadata: <String, Object?>{'code': e.code},
      );
      return false;
    }
  }

  @override
  Future<bool> startVpn(EasyTierConfig config) async {
    return _startInstance(config, useAndroidVpn: true);
  }

  @override
  Future<bool> startNoTun(EasyTierConfig config) async {
    return _startInstance(
      await _prepareNoTunConfig(config),
      useAndroidVpn: false,
    );
  }

  Future<EasyTierConfig> _prepareNoTunConfig(EasyTierConfig config) async {
    final socks5Port = await _resolveNoTunSocksPort(config.socks5Port);
    return config.copyWith(
      noTun: true,
      enableKcpProxy: true,
      enableQuicProxy: true,
      socks5Port: socks5Port,
      portForwards: const <String>[],
      portMappings: const <EasyTierPortMapping>[],
    );
  }

  Future<int> _resolveNoTunSocksPort(int? preferredPort) async {
    final preferred = preferredPort ?? noTunSocksPort;
    if (await _isLoopbackPortAvailable(preferred)) {
      return preferred;
    }

    for (var port = noTunSocksPort + 1; port <= noTunSocksPort + 40; port++) {
      if (await _isLoopbackPortAvailable(port)) {
        return port;
      }
    }

    return preferred;
  }

  Future<bool> _isLoopbackPortAvailable(int port) async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      return true;
    } on SocketException {
      return false;
    } finally {
      await socket?.close();
    }
  }

  Future<bool> _startInstance(
    EasyTierConfig config, {
    required bool useAndroidVpn,
  }) async {
    try {
      final configString = config.toToml();
      _configString = configString;

      recordRuntimeLog(
        'EasyTier',
        'Starting network instance',
        metadata: <String, Object?>{
          'instanceName': config.instanceName,
          'useAndroidVpn': useAndroidVpn,
          'configLength': configString.length,
        },
      );
      final result = await _channel.invokeMethod<bool>('startVpn', {
        'config': configString,
        'instanceName': config.instanceName,
        'useAndroidVpn': useAndroidVpn,
      });

      if (result == true) {
        _isRunning = true;
        _currentInstanceName = config.instanceName;
        _usesAndroidVpn = useAndroidVpn;
        _activeNoTunSocksPort = useAndroidVpn ? null : config.socks5Port;
        _lastError = null;
        recordRuntimeLog(
          'EasyTier',
          'Network instance started',
          metadata: <String, Object?>{
            'instanceName': config.instanceName,
            'useAndroidVpn': useAndroidVpn,
            'socks5Port': _activeNoTunSocksPort,
          },
        );
        return true;
      } else {
        _lastError = await getLastError();
        if (!useAndroidVpn) {
          _activeNoTunSocksPort = null;
        }
        recordRuntimeLog(
          'EasyTier',
          'Network instance start returned failure',
          error: _lastError,
          metadata: <String, Object?>{
            'instanceName': config.instanceName,
            'useAndroidVpn': useAndroidVpn,
          },
        );
        return false;
      }
    } on PlatformException catch (e, stackTrace) {
      _isRunning = false;
      _activeNoTunSocksPort = null;
      _lastError = e.message;
      recordRuntimeLog(
        'EasyTier',
        'Network instance start threw an exception',
        error: e,
        stackTrace: stackTrace,
        metadata: <String, Object?>{
          'code': e.code,
          'instanceName': config.instanceName,
          'useAndroidVpn': useAndroidVpn,
        },
      );
      return false;
    }
  }

  @override
  Future<void> stopVpn() async {
    try {
      recordRuntimeLog('EasyTier', 'Stopping network instance');
      await _channel.invokeMethod('stopVpn');
      _isRunning = false;
      _currentInstanceName = null;
      _usesAndroidVpn = true;
      _activeNoTunSocksPort = null;
      recordRuntimeLog('EasyTier', 'Network instance stopped');
    } on PlatformException catch (e, stackTrace) {
      _lastError = e.message;
      recordRuntimeLog(
        'EasyTier',
        'Network instance stop failed',
        error: e,
        stackTrace: stackTrace,
        metadata: <String, Object?>{'code': e.code},
      );
    }
  }

  Future<Map<String, dynamic>?> getNetworkInfo() async {
    try {
      developer.log('Getting network info', name: 'EasyTier');
      final info = await _channel.invokeMethod<String>('getNetworkInfo');
      if (info != null && info.isNotEmpty) {
        _lastRawNetworkInfo = info;
        try {
          final decoded = jsonDecode(info);
          if (decoded is Map<String, dynamic>) {
            developer.log(
              'Network info received: keys=${decoded.length}',
              name: 'EasyTier',
            );
            return decoded;
          }
          developer.log(
            'Network info JSON was not a map: ${decoded.runtimeType}',
            name: 'EasyTier',
          );
          return <String, dynamic>{'raw': info};
        } catch (e, stackTrace) {
          developer.log(
            'Network info was not JSON, using raw payload',
            name: 'EasyTier',
            error: e,
            stackTrace: stackTrace,
          );
          return <String, dynamic>{'raw': info};
        }
      }
      _lastRawNetworkInfo = null;
      return null;
    } on PlatformException catch (e, stackTrace) {
      _lastError = e.message;
      _lastRawNetworkInfo = null;
      recordRuntimeLog(
        'EasyTier',
        'Network information request failed',
        error: e,
        stackTrace: stackTrace,
        metadata: <String, Object?>{'code': e.code},
      );
      return null;
    } catch (e, stackTrace) {
      recordRuntimeLog(
        'EasyTier',
        'Unexpected network information error',
        error: e,
        stackTrace: stackTrace,
      );
      _lastRawNetworkInfo = null;
      return null;
    }
  }

  Future<String?> getLastError() async {
    try {
      final error = await _channel.invokeMethod<String>('getLastError');
      _lastError = error;
      return error;
    } on PlatformException catch (e) {
      return e.message;
    }
  }
}
