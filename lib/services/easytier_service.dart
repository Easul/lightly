import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import '../models/easytier_config.dart';

class EasyTierService {
  static const MethodChannel _channel = MethodChannel('easytier_vpn');

  static final EasyTierService _instance = EasyTierService._internal();
  factory EasyTierService() => _instance;
  EasyTierService._internal();

  bool _isRunning = false;
  String? _lastError;
  String? _configString;
  String? _lastRawNetworkInfo;

  bool get isRunning => _isRunning;
  String? get lastError => _lastError;
  String? get configString => _configString;
  String? get lastRawNetworkInfo => _lastRawNetworkInfo;

  Future<bool> parseConfig(String config) async {
    try {
      developer.log('Parsing EasyTier config', name: 'EasyTier');
      final result = await _channel.invokeMethod<bool>('parseConfig', {
        'config': config,
      });
      developer.log('Config parse result: $result', name: 'EasyTier');
      return result ?? false;
    } on PlatformException catch (e) {
      _lastError = e.message;
      developer.log(
        'Config parse error: ${e.message}',
        name: 'EasyTier',
        error: e,
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
    } on PlatformException catch (e) {
      developer.log(
        'VPN permission check error: ${e.message}',
        name: 'EasyTier',
        error: e,
      );
      return false;
    }
  }

  Future<bool> startVpn(EasyTierConfig config) async {
    try {
      final configString = config.toToml();
      _configString = configString;

      developer.log(
        'Starting VPN with config length: ${configString.length}',
        name: 'EasyTier',
      );
      final result = await _channel.invokeMethod<bool>('startVpn', {
        'config': configString,
        'instanceName': config.instanceName,
      });

      if (result == true) {
        _isRunning = true;
        _lastError = null;
        developer.log('VPN started successfully', name: 'EasyTier');
        return true;
      } else {
        _lastError = await getLastError();
        developer.log('VPN start failed: $_lastError', name: 'EasyTier');
        return false;
      }
    } on PlatformException catch (e) {
      _isRunning = false;
      _lastError = e.message;
      developer.log(
        'VPN start exception: ${e.message}',
        name: 'EasyTier',
        error: e,
      );
      return false;
    }
  }

  Future<void> stopVpn() async {
    try {
      developer.log('Stopping VPN', name: 'EasyTier');
      await _channel.invokeMethod('stopVpn');
      _isRunning = false;
      developer.log('VPN stopped', name: 'EasyTier');
    } on PlatformException catch (e) {
      _lastError = e.message;
      developer.log('VPN stop error: ${e.message}', name: 'EasyTier', error: e);
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
              'Network info received as JSON map: $decoded',
              name: 'EasyTier',
            );
            return decoded;
          }
          developer.log(
            'Network info JSON was not a map: $decoded',
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
    } on PlatformException catch (e) {
      _lastError = e.message;
      _lastRawNetworkInfo = null;
      developer.log(
        'Get network info error: ${e.message}',
        name: 'EasyTier',
        error: e,
      );
      return null;
    } catch (e, stackTrace) {
      developer.log(
        'Unexpected getNetworkInfo error: $e',
        name: 'EasyTier',
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
