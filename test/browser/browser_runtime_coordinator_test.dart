import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/services/browser_runtime_coordinator.dart';

void main() {
  test('restores proxy local HTTP and clipboard once', () async {
    final harness = _BrowserRuntimeHarness(
      settings: BrowserSettings.defaults().copyWith(
        proxyEnabled: true,
        proxyHost: 'proxy.example',
        proxyPort: 8080,
        localHttpServerEnabled: true,
      ),
      clipboardEnabled: true,
      clipboardPort: 12345,
    );

    final first = await harness.runtime.initializePersistedServices(
      enableWebView: true,
    );
    final second = await harness.runtime.initializePersistedServices(
      enableWebView: true,
    );

    expect(first.isProxyActive, isTrue);
    expect(second.isProxyActive, isTrue);
    expect(harness.loadSettingsCalls, 1);
    expect(harness.applyProxyCalls, 1);
    expect(harness.applyLocalHttpCalls, 1);
    expect(harness.startClipboardCalls, 1);
    expect(harness.startedClipboardPort, 12345);
  });

  test('reuses an applied settings fingerprint unless forced', () async {
    final settings = BrowserSettings.defaults();
    final harness = _BrowserRuntimeHarness(settings: settings);

    await harness.runtime.applySettings(settings, enableWebView: true);
    await harness.runtime.applySettings(settings, enableWebView: true);
    await harness.runtime.applySettings(
      settings,
      enableWebView: true,
      force: true,
    );

    expect(harness.clearProxyCalls, 2);
    expect(harness.applyLocalHttpCalls, 2);
  });

  test('reports proxy errors while still applying local HTTP', () async {
    final harness = _BrowserRuntimeHarness(
      settings: BrowserSettings.defaults().copyWith(
        proxyEnabled: true,
        proxyHost: 'proxy.example',
        proxyPort: 8080,
      ),
      proxyError: StateError('proxy failed'),
    );

    final state = await harness.runtime.applySettings(
      harness.settings,
      enableWebView: true,
    );

    expect(state.isProxyActive, isFalse);
    expect(state.proxyStatusMessage, 'formatted: proxy failed');
    expect(harness.applyLocalHttpCalls, 1);
  });

  test('can surface or swallow local HTTP failures', () async {
    final settings = BrowserSettings.defaults();
    final swallowed = _BrowserRuntimeHarness(
      settings: settings,
      localHttpError: StateError('bind failed'),
    );
    final surfaced = _BrowserRuntimeHarness(
      settings: settings,
      localHttpError: StateError('bind failed'),
    );

    await swallowed.runtime.applySettings(settings, enableWebView: false);
    await expectLater(
      surfaced.runtime.applySettings(
        settings,
        enableWebView: false,
        swallowLocalHttpErrors: false,
      ),
      throwsStateError,
    );
  });

  test('shutdown attempts every browser runtime owner', () async {
    final harness = _BrowserRuntimeHarness(
      settings: BrowserSettings.defaults(),
    );

    await harness.runtime.shutdown();

    expect(harness.stopClipboardCalls, 1);
    expect(harness.stopLocalHttpCalls, 1);
    expect(harness.clearProxyCalls, 1);
  });
}

class _BrowserRuntimeHarness {
  _BrowserRuntimeHarness({
    required this.settings,
    this.clipboardEnabled = false,
    this.clipboardPort,
    this.proxyError,
    this.localHttpError,
  }) {
    runtime = BrowserRuntimeCoordinator(
      loadSettings: () async {
        loadSettingsCalls += 1;
        return settings;
      },
      isProxySupported: () async => true,
      applyProxy: (_) async {
        applyProxyCalls += 1;
        if (proxyError != null) throw proxyError!;
      },
      clearProxy: () async {
        clearProxyCalls += 1;
      },
      describeProxyError: (error) => 'formatted: ${_errorMessage(error)}',
      applyLocalHttpSettings: (_) async {
        applyLocalHttpCalls += 1;
        if (localHttpError != null) throw localHttpError!;
      },
      stopLocalHttp: () async {
        stopLocalHttpCalls += 1;
      },
      loadClipboardEnabled: () async => clipboardEnabled,
      loadClipboardPort: () async => clipboardPort,
      isClipboardRunning: () => clipboardRunning,
      startClipboard: ({int? preferredPort}) async {
        startClipboardCalls += 1;
        startedClipboardPort = preferredPort;
        clipboardRunning = true;
      },
      stopClipboard: () async {
        stopClipboardCalls += 1;
        clipboardRunning = false;
      },
    );
  }

  final BrowserSettings settings;
  final bool clipboardEnabled;
  final int? clipboardPort;
  final Object? proxyError;
  final Object? localHttpError;
  late final BrowserRuntimeCoordinator runtime;

  int loadSettingsCalls = 0;
  int applyProxyCalls = 0;
  int clearProxyCalls = 0;
  int applyLocalHttpCalls = 0;
  int stopLocalHttpCalls = 0;
  int startClipboardCalls = 0;
  int stopClipboardCalls = 0;
  int? startedClipboardPort;
  bool clipboardRunning = false;

  String _errorMessage(Object error) {
    if (error is StateError) {
      return error.message;
    }
    return error.toString();
  }
}
