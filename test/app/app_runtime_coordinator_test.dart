import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/app/app_runtime_coordinator.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/services/browser_runtime_coordinator.dart';
import 'package:lightly/core/logging/runtime_logger.dart';
import 'package:lightly/models/easytier_config.dart';
import 'package:lightly/models/easytier_network_profile.dart';
import 'package:lightly/services/easytier_profile_service.dart';
import 'package:lightly/services/easytier_runtime.dart';
import 'package:lightly/services/remote_control_runtime.dart';
import 'package:lightly/features/local_sharing/simple_file_manager/simple_file_manager_runtime.dart';
import 'package:lightly/features/local_sharing/simple_file_manager/simple_file_manager_settings.dart';

void main() {
  test(
    'restores enabled persisted services once and resets native state',
    () async {
      final files = _FakeSimpleFileManagerRuntime(enabled: true);
      final platform = _FakeRemoteControlPlatformRuntime();
      final coordinator = AppRuntimeCoordinator(
        simpleFileManager: files,
        easyTier: _FakeEasyTierRuntime(),
        easyTierProfiles: _FakeEasyTierProfiles(),
        remoteControl: _FakeRemoteControlRuntime(),
        remoteControlPlatform: platform,
        browserRuntime: _FakeBrowserRuntimePolicy(),
        logger: _RecordingRuntimeLogger(),
      );

      await coordinator.initializePersistedServices();
      await coordinator.initializePersistedServices();

      expect(files.loadCalls, 1);
      expect(files.startCalls, 1);
      expect(platform.stopCalls, 1);
      expect(platform.stopCaptureCalls, 1);
    },
  );

  test('records persisted service startup failures', () async {
    final files = _FakeSimpleFileManagerRuntime(
      enabled: true,
      startError: StateError('bind failed'),
    );
    final logger = _RecordingRuntimeLogger();
    final coordinator = AppRuntimeCoordinator(
      simpleFileManager: files,
      easyTier: _FakeEasyTierRuntime(),
      easyTierProfiles: _FakeEasyTierProfiles(),
      remoteControl: _FakeRemoteControlRuntime(),
      remoteControlPlatform: _FakeRemoteControlPlatformRuntime(),
      browserRuntime: _FakeBrowserRuntimePolicy(),
      logger: logger,
    );

    await coordinator.initializePersistedServices();

    expect(logger.unhandledErrors, hasLength(1));
  });

  test('reuses an existing no-tun EasyTier runtime', () async {
    final easyTier = _FakeEasyTierRuntime(isRunning: true, isNoTunMode: true);
    final coordinator = _coordinator(easyTier: easyTier);

    final started = await coordinator.ensureEasyTierForRemoteControl(
      noTunMode: true,
    );

    expect(started, isTrue);
    expect(easyTier.stopCalls, 0);
    expect(easyTier.startNoTunCalls, 0);
  });

  test(
    'switches a running VPN runtime before starting selected no-tun profile',
    () async {
      final easyTier = _FakeEasyTierRuntime(isRunning: true);
      final profiles = _FakeEasyTierProfiles(selectedId: 'selected');
      final coordinator = _coordinator(
        easyTier: easyTier,
        easyTierProfiles: profiles,
      );

      final started = await coordinator.ensureEasyTierForRemoteControl(
        noTunMode: true,
      );

      expect(started, isTrue);
      expect(easyTier.stopCalls, 1);
      expect(easyTier.startNoTunCalls, 1);
      expect(easyTier.lastConfig?.networkName, 'selected-network');
    },
  );

  test(
    'coalesces concurrent shutdown and continues after owner failure',
    () async {
      final disconnectGate = Completer<void>();
      final remote = _FakeRemoteControlRuntime(
        disconnectGate: disconnectGate,
        disconnectError: StateError('socket close failed'),
      );
      final easyTier = _FakeEasyTierRuntime(isRunning: true);
      final platform = _FakeRemoteControlPlatformRuntime();
      final logger = _RecordingRuntimeLogger();
      final files = _FakeSimpleFileManagerRuntime();
      final coordinator = AppRuntimeCoordinator(
        simpleFileManager: files,
        easyTier: easyTier,
        easyTierProfiles: _FakeEasyTierProfiles(),
        remoteControl: remote,
        remoteControlPlatform: platform,
        browserRuntime: _FakeBrowserRuntimePolicy(),
        logger: logger,
      );

      final first = coordinator.shutdownAll();
      final second = coordinator.shutdownAll();
      disconnectGate.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(remote.disconnectCalls, 1);
      expect(files.stopCalls, 1);
      expect(easyTier.stopCalls, 1);
      expect(platform.stopCalls, 1);
      expect(platform.stopCaptureCalls, 1);
      expect(
        logger.messages,
        contains('[AppRuntime] Remote control shutdown failed'),
      );
    },
  );

  test('detached lifecycle delegates to shutdown policy', () async {
    final easyTier = _FakeEasyTierRuntime(isRunning: true);
    final coordinator = _coordinator(easyTier: easyTier);

    await coordinator.handleLifecycleState(AppLifecycleState.detached);

    expect(easyTier.stopCalls, 1);
  });

  test('receiver host cleanup is delegated back to runtime policy', () async {
    final remote = _FakeRemoteControlRuntime();
    final easyTier = _FakeEasyTierRuntime(isRunning: true);
    final platform = _FakeRemoteControlPlatformRuntime();
    AppRuntimeCoordinator(
      simpleFileManager: _FakeSimpleFileManagerRuntime(),
      easyTier: easyTier,
      easyTierProfiles: _FakeEasyTierProfiles(),
      remoteControl: remote,
      remoteControlPlatform: platform,
      browserRuntime: _FakeBrowserRuntimePolicy(),
      logger: _RecordingRuntimeLogger(),
    );

    await remote.receiverHostShutdownHandler!();

    expect(remote.disconnectCalls, 1);
    expect(easyTier.stopCalls, 1);
    expect(platform.stopCalls, 1);
    expect(platform.stopCaptureCalls, 1);
  });
}

AppRuntimeCoordinator _coordinator({
  required _FakeEasyTierRuntime easyTier,
  _FakeEasyTierProfiles? easyTierProfiles,
}) {
  return AppRuntimeCoordinator(
    simpleFileManager: _FakeSimpleFileManagerRuntime(),
    easyTier: easyTier,
    easyTierProfiles: easyTierProfiles ?? _FakeEasyTierProfiles(),
    remoteControl: _FakeRemoteControlRuntime(),
    remoteControlPlatform: _FakeRemoteControlPlatformRuntime(),
    browserRuntime: _FakeBrowserRuntimePolicy(),
    logger: _RecordingRuntimeLogger(),
  );
}

class _FakeSimpleFileManagerRuntime implements SimpleFileManagerRuntime {
  _FakeSimpleFileManagerRuntime({this.enabled = false, this.startError});

  final bool enabled;
  final Object? startError;
  int loadCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<SimpleFileManagerSettings> loadSettings() async {
    loadCalls += 1;
    return SimpleFileManagerSettings.defaults().copyWith(enabled: enabled);
  }

  @override
  Future<void> applySettings(SimpleFileManagerSettings settings) async {
    await start(settings: settings);
  }

  @override
  Future<void> start({SimpleFileManagerSettings? settings}) async {
    startCalls += 1;
    if (startError != null) {
      throw startError!;
    }
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }
}

class _FakeBrowserRuntimePolicy implements BrowserRuntimePolicy {
  int initializeCalls = 0;
  int shutdownCalls = 0;

  @override
  Future<BrowserRuntimeState> initializePersistedServices({
    required bool enableWebView,
  }) async {
    initializeCalls += 1;
    return _state();
  }

  @override
  Future<BrowserRuntimeState> applySettings(
    BrowserSettings settings, {
    required bool enableWebView,
    bool swallowLocalHttpErrors = true,
    bool force = false,
  }) async {
    return _state(settings);
  }

  @override
  Future<void> ensureClipboardServer() async {}

  @override
  Future<void> shutdown() async {
    shutdownCalls += 1;
  }

  BrowserRuntimeState _state([BrowserSettings? settings]) {
    return BrowserRuntimeState(
      settings: settings ?? BrowserSettings.defaults(),
      proxySupported: false,
      isProxyActive: false,
      proxyStatusMessage: '',
    );
  }
}

class _FakeEasyTierRuntime implements EasyTierRuntime {
  _FakeEasyTierRuntime({this.isRunning = false, this.isNoTunMode = false});

  @override
  bool isRunning;

  @override
  bool isNoTunMode;

  int startVpnCalls = 0;
  int startNoTunCalls = 0;
  int stopCalls = 0;
  EasyTierConfig? lastConfig;

  @override
  Future<bool> startNoTun(EasyTierConfig config) async {
    startNoTunCalls += 1;
    lastConfig = config;
    isRunning = true;
    isNoTunMode = true;
    return true;
  }

  @override
  Future<bool> startVpn(EasyTierConfig config) async {
    startVpnCalls += 1;
    lastConfig = config;
    isRunning = true;
    isNoTunMode = false;
    return true;
  }

  @override
  Future<void> stopVpn() async {
    stopCalls += 1;
    isRunning = false;
    isNoTunMode = false;
  }
}

class _FakeEasyTierProfiles extends EasyTierProfileService {
  _FakeEasyTierProfiles({this.selectedId});

  final String? selectedId;

  @override
  Future<String?> getSelectedProfileId() async => selectedId;

  @override
  Future<List<EasyTierNetworkProfile>> loadProfiles() async {
    return <EasyTierNetworkProfile>[
      _profile('first', 'first-network'),
      _profile('selected', 'selected-network'),
    ];
  }

  EasyTierNetworkProfile _profile(String id, String networkName) {
    final now = DateTime(2026);
    return EasyTierNetworkProfile(
      id: id,
      name: networkName,
      config: EasyTierConfig(instanceName: id, networkName: networkName),
      createdAt: now,
      updatedAt: now,
    );
  }
}

class _FakeRemoteControlRuntime implements RemoteControlRuntime {
  _FakeRemoteControlRuntime({this.disconnectGate, this.disconnectError});

  final Completer<void>? disconnectGate;
  final Object? disconnectError;
  int disconnectCalls = 0;
  Future<void> Function()? receiverHostShutdownHandler;

  @override
  Future<void> disconnect() async {
    disconnectCalls += 1;
    await disconnectGate?.future;
    if (disconnectError != null) {
      throw disconnectError!;
    }
  }

  @override
  void setReceiverHostShutdownHandler(Future<void> Function()? handler) {
    receiverHostShutdownHandler = handler;
  }
}

class _FakeRemoteControlPlatformRuntime
    implements RemoteControlPlatformRuntime {
  int stopCalls = 0;
  int stopCaptureCalls = 0;

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<void> stopScreenCapture() async {
    stopCaptureCalls += 1;
  }
}

class _RecordingRuntimeLogger implements RuntimeLogger {
  final List<String> messages = <String>[];
  final List<Object> unhandledErrors = <Object>[];

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
  }

  @override
  Future<void> logFlutterError(FlutterErrorDetails details) async {}

  @override
  Future<void> logUnhandledError(Object error, StackTrace stackTrace) async {
    unhandledErrors.add(error);
  }
}
