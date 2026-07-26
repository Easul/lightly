import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import '../browser/services/browser_runtime_coordinator.dart';
import '../core/logging/runtime_logger.dart';
import '../features/easytier/domain/easytier_config.dart';
import '../features/easytier/domain/easytier_network_profile.dart';
import '../features/easytier/domain/easytier_runtime.dart';
import '../features/easytier/infrastructure/easytier_profile_service.dart';
import '../features/easytier/infrastructure/easytier_service.dart';
import '../features/remote_control/domain/remote_control_runtime.dart';
import '../services/app_log_service.dart';
import '../services/remote_control_platform_gateway.dart';
import '../services/remote_control_service.dart';
import '../features/local_sharing/simple_file_manager/simple_file_manager_runtime.dart';
import '../features/local_sharing/simple_file_manager/simple_file_manager_service.dart';

/// Application-level policy for persisted and lifecycle-sensitive runtimes.
///
/// Services remain the owners of sockets, servers, and native state. This
/// coordinator only decides when those owners should start or stop.
class AppRuntimeCoordinator {
  AppRuntimeCoordinator({
    SimpleFileManagerRuntime? simpleFileManager,
    EasyTierRuntime? easyTier,
    EasyTierProfileService? easyTierProfiles,
    RemoteControlRuntime? remoteControl,
    RemoteControlPlatformRuntime? remoteControlPlatform,
    BrowserRuntimePolicy? browserRuntime,
    RuntimeLogger? logger,
  }) : _simpleFileManager = simpleFileManager ?? SimpleFileManagerService(),
       _easyTier = easyTier ?? EasyTierService(),
       _easyTierProfiles = easyTierProfiles ?? EasyTierProfileService(),
       _remoteControl = remoteControl ?? RemoteControlService(),
       _remoteControlPlatform =
           remoteControlPlatform ?? RemoteControlPlatformGateway.instance,
       _browserRuntime = browserRuntime ?? BrowserRuntimeCoordinator.instance,
       _logger = logger ?? AppLogService.instance {
    _remoteControl.setReceiverHostShutdownHandler(
      shutdownRemoteControlHostResources,
    );
  }

  static final AppRuntimeCoordinator instance = AppRuntimeCoordinator();

  final SimpleFileManagerRuntime _simpleFileManager;
  final EasyTierRuntime _easyTier;
  final EasyTierProfileService _easyTierProfiles;
  final RemoteControlRuntime _remoteControl;
  final RemoteControlPlatformRuntime _remoteControlPlatform;
  final BrowserRuntimePolicy _browserRuntime;
  final RuntimeLogger _logger;

  Future<void>? _initialization;
  Future<void>? _shutdown;
  Future<void>? _remoteHostShutdown;

  Future<void> initializePersistedServices() {
    return _initialization ??= _initializePersistedServices();
  }

  Future<void> _initializePersistedServices() async {
    await _ensureDefaultNativeState();

    try {
      final settings = await _simpleFileManager.loadSettings();
      if (settings.enabled) {
        await _simpleFileManager.start(settings: settings);
      }
    } catch (error, stackTrace) {
      await _logger.logUnhandledError(error, stackTrace);
    }

    try {
      await _browserRuntime.initializePersistedServices(enableWebView: !kIsWeb);
    } catch (error, stackTrace) {
      await _logger.logUnhandledError(error, stackTrace);
    }
  }

  Future<void> _ensureDefaultNativeState() async {
    try {
      await _remoteControlPlatform.stop();
    } catch (_) {}

    try {
      await _remoteControlPlatform.stopScreenCapture();
    } catch (_) {}
  }

  Future<bool> ensureEasyTierForRemoteControl({bool noTunMode = false}) async {
    if (noTunMode) {
      if (_easyTier.isNoTunMode) {
        return true;
      }
      if (_easyTier.isRunning) {
        await _easyTier.stopVpn();
      }
      return _startSelectedEasyTierProfile(useAndroidVpn: false);
    }

    if (_easyTier.isRunning) {
      return true;
    }
    return _startSelectedEasyTierProfile(useAndroidVpn: true);
  }

  Future<void> applySimpleFileManagerSettings(
    SimpleFileManagerSettings settings,
  ) {
    return _simpleFileManager.applySettings(settings);
  }

  Future<bool> startEasyTier(
    EasyTierConfig config, {
    required bool useNoTunMode,
  }) {
    return useNoTunMode
        ? _easyTier.startNoTun(config)
        : _easyTier.startVpn(config);
  }

  Future<void> stopEasyTier() => _easyTier.stopVpn();

  Future<bool> _startSelectedEasyTierProfile({
    required bool useAndroidVpn,
  }) async {
    try {
      final selectedId = await _easyTierProfiles.getSelectedProfileId();
      final profiles = await _easyTierProfiles.loadProfiles();
      final target = _selectProfile(profiles, selectedId);
      if (target == null) {
        return false;
      }
      return useAndroidVpn
          ? _easyTier.startVpn(target.config)
          : _easyTier.startNoTun(target.config);
    } catch (error, stackTrace) {
      await _logger.log(
        '[AppRuntime] Failed to start EasyTier for remote control',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  EasyTierNetworkProfile? _selectProfile(
    List<EasyTierNetworkProfile> profiles,
    String? selectedId,
  ) {
    if (profiles.isEmpty) {
      return null;
    }
    if (selectedId == null) {
      return profiles.first;
    }
    return profiles.firstWhere(
      (profile) => profile.id == selectedId,
      orElse: () => profiles.first,
    );
  }

  Future<void> handleLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.detached) {
      await shutdownAll();
    }
  }

  Future<void> shutdownAll() {
    final activeShutdown = _shutdown;
    if (activeShutdown != null) {
      return activeShutdown;
    }
    final shutdown = _shutdownAll();
    _shutdown = shutdown;
    return shutdown.whenComplete(() {
      if (identical(_shutdown, shutdown)) {
        _shutdown = null;
      }
    });
  }

  Future<void> _shutdownAll() async {
    try {
      await _simpleFileManager.stop();
    } catch (error, stackTrace) {
      await _logger.log(
        '[AppRuntime] Simple file manager shutdown failed',
        error: error,
        stackTrace: stackTrace,
      );
    }

    await shutdownRemoteControlHostResources();

    await _browserRuntime.shutdown();
  }

  Future<void> shutdownRemoteControlHostResources() {
    final activeShutdown = _remoteHostShutdown;
    if (activeShutdown != null) {
      return activeShutdown;
    }
    final shutdown = _shutdownRemoteControlHostResources();
    _remoteHostShutdown = shutdown;
    return shutdown.whenComplete(() {
      if (identical(_remoteHostShutdown, shutdown)) {
        _remoteHostShutdown = null;
      }
    });
  }

  Future<void> _shutdownRemoteControlHostResources() async {
    try {
      await _remoteControl.disconnect();
    } catch (error, stackTrace) {
      await _logger.log(
        '[AppRuntime] Remote control shutdown failed',
        error: error,
        stackTrace: stackTrace,
      );
    }

    await _easyTier.stopVpn();

    try {
      await _remoteControlPlatform.stop();
    } catch (_) {}

    try {
      await _remoteControlPlatform.stopScreenCapture();
    } catch (_) {}
  }
}
