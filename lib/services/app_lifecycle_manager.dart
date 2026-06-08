import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/easytier_network_profile.dart';
import '../services/easytier_service.dart';
import '../services/easytier_profile_service.dart';
import '../services/remote_control_service.dart';

class AppLifecycleManager extends WidgetsBindingObserver {
  static final AppLifecycleManager _instance = AppLifecycleManager._internal();
  factory AppLifecycleManager() => _instance;
  AppLifecycleManager._internal();

  final EasyTierService _easyTierService = EasyTierService();
  final EasyTierProfileService _profileService = EasyTierProfileService();
  final RemoteControlService _remoteControlService = RemoteControlService();
  static const MethodChannel _channel = MethodChannel('remote_control');

  bool _isShuttingDown = false;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    WidgetsBinding.instance.addObserver(this);
    await _ensureDefaultServiceStates();
    _isInitialized = true;
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
  }

  /// 应用启动时确保服务默认关闭状态（首次启动或强制关闭后）
  Future<void> _ensureDefaultServiceStates() async {
    try {
      // 默认关闭无障碍服务
      await _channel.invokeMethod('stop');
    } catch (_) {
      // 可能已经关闭或未启动
    }

    try {
      // 默认关闭屏幕录制
      await _channel.invokeMethod('stopScreenCapture');
    } catch (_) {
      // 可能已经关闭或未启动
    }
  }

  /// 在应用真正退出时调用（从浏览器页面退出按钮）
  Future<void> shutdownAllServices() async {
    if (_isShuttingDown) return;
    _isShuttingDown = true;

    // 关闭远程控制服务
    await _remoteControlService.disconnect();

    // 关闭 VPN
    await _easyTierService.stopVpn();

    // 关闭无障碍服务和屏幕录制
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}

    try {
      await _channel.invokeMethod('stopScreenCapture');
    } catch (_) {}

    _isShuttingDown = false;
  }

  /// 远程控制被控端启动时检查并启动 VPN
  Future<bool> ensureVpnForRemoteControl({bool noTunMode = false}) async {
    if (noTunMode) {
      if (_easyTierService.isRunning) {
        await _easyTierService.stopVpn();
      }
      return _startSelectedEasyTierProfile(useAndroidVpn: false);
    }

    if (_easyTierService.isRunning) {
      return true;
    }

    return _startSelectedEasyTierProfile(useAndroidVpn: true);
  }

  Future<bool> _startSelectedEasyTierProfile({
    required bool useAndroidVpn,
  }) async {
    try {
      final selectedId = await _profileService.getSelectedProfileId();
      final profiles = await _profileService.loadProfiles();

      EasyTierNetworkProfile? targetProfile;
      if (selectedId != null) {
        targetProfile = profiles.firstWhere(
          (p) => p.id == selectedId,
          orElse: () => profiles.first,
        );
      } else {
        targetProfile = profiles.isNotEmpty ? profiles.first : null;
      }

      if (targetProfile == null) {
        return false;
      }

      if (useAndroidVpn) {
        return await _easyTierService.startVpn(targetProfile.config);
      }
      return await _easyTierService.startNoTun(targetProfile.config);
    } catch (e) {
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 不在普通页面切换时关闭服务
    // 只在真正的应用级别生命周期事件时处理
    switch (state) {
      case AppLifecycleState.detached:
        // 应用被强制关闭时
        unawaited(shutdownAllServices());
        break;
      default:
        break;
    }
  }
}
