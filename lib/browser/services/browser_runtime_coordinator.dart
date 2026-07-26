import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../features/local_sharing/local_http/local_http_server_config.dart';
import '../browser_settings.dart';
import 'browser_shared_services.dart';

class BrowserRuntimeState {
  const BrowserRuntimeState({
    required this.settings,
    required this.proxySupported,
    required this.isProxyActive,
    required this.proxyStatusMessage,
  });

  final BrowserSettings settings;
  final bool proxySupported;
  final bool isProxyActive;
  final String proxyStatusMessage;
}

abstract class BrowserRuntimePolicy {
  Future<BrowserRuntimeState> initializePersistedServices({
    required bool enableWebView,
  });

  Future<BrowserRuntimeState> applySettings(
    BrowserSettings settings, {
    required bool enableWebView,
    bool swallowLocalHttpErrors = true,
    bool force = false,
  });

  Future<void> ensureClipboardServer();

  Future<void> shutdown();
}

/// Owns application policy for browser-adjacent background runtimes.
///
/// Proxy, local HTTP, and clipboard services continue to own their resources;
/// this class only coordinates persisted settings and start/stop timing.
class BrowserRuntimeCoordinator implements BrowserRuntimePolicy {
  BrowserRuntimeCoordinator({
    required Future<BrowserSettings> Function() loadSettings,
    required Future<bool> Function() isProxySupported,
    required Future<void> Function(BrowserSettings) applyProxy,
    required Future<void> Function() clearProxy,
    required String Function(Object) describeProxyError,
    required Future<void> Function(BrowserSettings) applyLocalHttpSettings,
    required Future<void> Function() stopLocalHttp,
    required Future<bool> Function() loadClipboardEnabled,
    required Future<int?> Function() loadClipboardPort,
    required bool Function() isClipboardRunning,
    required Future<void> Function({int? preferredPort}) startClipboard,
    required Future<void> Function() stopClipboard,
  }) : _loadSettings = loadSettings,
       _isProxySupported = isProxySupported,
       _applyProxy = applyProxy,
       _clearProxy = clearProxy,
       _describeProxyError = describeProxyError,
       _applyLocalHttpSettings = applyLocalHttpSettings,
       _stopLocalHttp = stopLocalHttp,
       _loadClipboardEnabled = loadClipboardEnabled,
       _loadClipboardPort = loadClipboardPort,
       _isClipboardRunning = isClipboardRunning,
       _startClipboard = startClipboard,
       _stopClipboard = stopClipboard;

  factory BrowserRuntimeCoordinator.production() {
    final services = BrowserSharedServices.instance;
    return BrowserRuntimeCoordinator(
      loadSettings: services.settingsService.loadSettings,
      isProxySupported: services.proxyService.isSupported,
      applyProxy: services.proxyService.applyProxy,
      clearProxy: services.proxyService.clearProxy,
      describeProxyError: services.proxyService.describeError,
      applyLocalHttpSettings: (settings) =>
          services.localHttpFileServerService.applySettings(
            LocalHttpServerConfig(
              enabled: settings.localHttpServerEnabled,
              rootPath: settings.localHttpRootPath,
              port: settings.localHttpServerPort,
              bindAllInterfaces: settings.localHttpBindAllInterfaces,
              uploadKey: settings.localHttpUploadKey,
            ),
          ),
      stopLocalHttp: services.localHttpFileServerService.stop,
      loadClipboardEnabled: services.clipboardStorage.loadServerEnabled,
      loadClipboardPort: services.clipboardStorage.loadServerPort,
      isClipboardRunning: () => services.clipboardService.isRunning,
      startClipboard: services.clipboardService.start,
      stopClipboard: services.clipboardService.stop,
    );
  }

  static final BrowserRuntimeCoordinator instance =
      BrowserRuntimeCoordinator.production();

  final Future<BrowserSettings> Function() _loadSettings;
  final Future<bool> Function() _isProxySupported;
  final Future<void> Function(BrowserSettings) _applyProxy;
  final Future<void> Function() _clearProxy;
  final String Function(Object) _describeProxyError;
  final Future<void> Function(BrowserSettings) _applyLocalHttpSettings;
  final Future<void> Function() _stopLocalHttp;
  final Future<bool> Function() _loadClipboardEnabled;
  final Future<int?> Function() _loadClipboardPort;
  final bool Function() _isClipboardRunning;
  final Future<void> Function({int? preferredPort}) _startClipboard;
  final Future<void> Function() _stopClipboard;

  String? _lastApplyFingerprint;
  BrowserRuntimeState? _lastState;
  Future<BrowserRuntimeState>? _initialization;

  @override
  Future<BrowserRuntimeState> initializePersistedServices({
    required bool enableWebView,
  }) {
    return _initialization ??= _initialize(enableWebView: enableWebView);
  }

  Future<BrowserRuntimeState> _initialize({required bool enableWebView}) async {
    final state = await applySettings(
      await _loadSettings(),
      enableWebView: enableWebView,
      swallowLocalHttpErrors: true,
      force: true,
    );
    await ensureClipboardServer();
    return state;
  }

  @override
  Future<BrowserRuntimeState> applySettings(
    BrowserSettings settings, {
    required bool enableWebView,
    bool swallowLocalHttpErrors = true,
    bool force = false,
  }) async {
    final fingerprint = _fingerprint(settings, enableWebView);
    final cached = _lastState;
    if (!force && cached != null && fingerprint == _lastApplyFingerprint) {
      return cached;
    }

    final proxySupported = enableWebView && !kIsWeb
        ? await _isProxySupported().catchError((_) => false)
        : false;
    var proxyStatusMessage = '';
    var isProxyActive = false;

    if (proxySupported) {
      if (settings.shouldApplyProxy) {
        try {
          await _applyProxy(settings);
          isProxyActive = true;
        } catch (error) {
          proxyStatusMessage = _describeProxyError(error);
        }
      } else {
        try {
          await _clearProxy();
        } catch (error) {
          proxyStatusMessage = _describeProxyError(error);
        }
      }
    }

    try {
      await _applyLocalHttpSettings(settings);
    } catch (_) {
      if (!swallowLocalHttpErrors) {
        rethrow;
      }
    }

    final state = BrowserRuntimeState(
      settings: settings,
      proxySupported: proxySupported,
      isProxyActive: isProxyActive,
      proxyStatusMessage: proxyStatusMessage,
    );
    _lastApplyFingerprint = fingerprint;
    _lastState = state;
    return state;
  }

  @override
  Future<void> ensureClipboardServer() async {
    try {
      final enabled = await _loadClipboardEnabled();
      if (!enabled || _isClipboardRunning()) {
        return;
      }
      await _startClipboard(preferredPort: await _loadClipboardPort());
    } catch (_) {}
  }

  Future<void> applyProxySettings(BrowserSettings settings) async {
    await _applyProxy(settings);
    _invalidateAppliedSettings();
  }

  Future<void> clearProxySettings() async {
    await _clearProxy();
    _invalidateAppliedSettings();
  }

  Future<void> applyLocalHttpSettings(BrowserSettings settings) async {
    await _applyLocalHttpSettings(settings);
    _invalidateAppliedSettings();
  }

  Future<void> stopLocalHttp() async {
    await _stopLocalHttp();
    _invalidateAppliedSettings();
  }

  Future<void> startClipboard({int? preferredPort}) async {
    await _startClipboard(preferredPort: preferredPort);
  }

  Future<void> stopClipboard() => _stopClipboard();

  @override
  Future<void> shutdown() async {
    try {
      await _stopClipboard();
    } catch (_) {}
    try {
      await _stopLocalHttp();
    } catch (_) {}
    try {
      await _clearProxy();
    } catch (_) {}
    _invalidateAppliedSettings();
    _initialization = null;
  }

  void _invalidateAppliedSettings() {
    _lastApplyFingerprint = null;
    _lastState = null;
  }

  String _fingerprint(BrowserSettings settings, bool enableWebView) {
    return '$enableWebView:${jsonEncode(settings.toJson())}';
  }
}
