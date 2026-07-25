import 'dart:async';

import 'package:flutter/widgets.dart';

import '../app/app_runtime_coordinator.dart';

/// Forwards Flutter lifecycle events to the application runtime policy.
class AppLifecycleManager extends WidgetsBindingObserver {
  AppLifecycleManager._internal();

  static final AppLifecycleManager _instance = AppLifecycleManager._internal();

  factory AppLifecycleManager() => _instance;

  final AppRuntimeCoordinator _runtimeCoordinator =
      AppRuntimeCoordinator.instance;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    WidgetsBinding.instance.addObserver(this);
    _isInitialized = true;
  }

  Future<void> dispose() async {
    if (!_isInitialized) return;
    WidgetsBinding.instance.removeObserver(this);
    _isInitialized = false;
  }

  Future<void> shutdownAllServices() => _runtimeCoordinator.shutdownAll();

  Future<bool> ensureVpnForRemoteControl({bool noTunMode = false}) {
    return _runtimeCoordinator.ensureEasyTierForRemoteControl(
      noTunMode: noTunMode,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_runtimeCoordinator.handleLifecycleState(state));
  }
}
