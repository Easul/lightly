import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/optional_plugins/domain/optional_plugin_download_settings.dart';
import 'package:lightly/features/optional_plugins/infrastructure/optional_plugin_download_settings_store.dart';
import 'package:lightly/features/optional_plugins/infrastructure/optional_plugin_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lightly/features/optional_plugins/infrastructure/optional_plugin_manifest_loader.dart';

void main() {
  const source =
      'https://github.com/Easul/lightly-plugins/releases/download/plugins-v1/plugin.apk';

  test('normalizes and validates HTTPS mirror prefixes', () {
    const settings = OptionalPluginDownloadSettings(
      mirrorPrefix: 'https://mirror.example/proxy',
    );

    expect(settings.validationError, isNull);
    expect(settings.normalizedMirrorPrefix, 'https://mirror.example/proxy/');
    expect(
      settings.mirrorUri(Uri.parse(source)).toString(),
      'https://mirror.example/proxy/$source',
    );
    expect(
      const OptionalPluginDownloadSettings(
        mirrorPrefix: 'http://mirror.example/',
      ).validationError,
      isNotNull,
    );
  });

  test('automatic plan uses proxy GitHub before direct mirror', () {
    final attempts = const OptionalPluginDownloadPlanner().plan(
      source: Uri.parse(source),
      settings: const OptionalPluginDownloadSettings(),
      proxyAvailable: true,
    );

    expect(attempts, hasLength(2));
    expect(attempts.first.uri.toString(), source);
    expect(attempts.first.useProxy, isTrue);
    expect(attempts.last.uri.host, 'ghfast.top');
    expect(attempts.last.useProxy, isFalse);
  });

  test('automatic plan uses direct GitHub when proxy is unavailable', () {
    final attempts = const OptionalPluginDownloadPlanner().plan(
      source: Uri.parse(source),
      settings: const OptionalPluginDownloadSettings(),
      proxyAvailable: false,
    );

    expect(attempts.first.label, 'GitHub（直连）');
    expect(attempts.first.useProxy, isFalse);
    expect(attempts.last.label, '镜像');
  });

  test('manual modes expose only the selected route', () {
    const planner = OptionalPluginDownloadPlanner();
    final github = planner.plan(
      source: Uri.parse(source),
      settings: const OptionalPluginDownloadSettings(
        mode: OptionalPluginDownloadMode.githubOnly,
      ),
      proxyAvailable: true,
    );
    final mirror = planner.plan(
      source: Uri.parse(source),
      settings: const OptionalPluginDownloadSettings(
        mode: OptionalPluginDownloadMode.mirrorOnly,
      ),
      proxyAvailable: true,
    );

    expect(github, hasLength(1));
    expect(github.single.useProxy, isTrue);
    expect(mirror, hasLength(1));
    expect(mirror.single.uri.host, 'ghfast.top');
    expect(mirror.single.useProxy, isFalse);
  });

  test('settings store round-trips versioned preferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final store = OptionalPluginDownloadSettingsStore(preferences: preferences);
    const expected = OptionalPluginDownloadSettings(
      mode: OptionalPluginDownloadMode.mirrorOnly,
      mirrorPrefix: 'https://mirror.example/gh/',
    );

    await store.save(expected);
    final restored = await store.load();

    expect(restored.mode, expected.mode);
    expect(restored.normalizedMirrorPrefix, expected.mirrorPrefix);
    expect(
      preferences.containsKey(OptionalPluginDownloadSettingsStore.storageKey),
      isTrue,
    );
  });

  test('slow route threshold waits for a sustained low transfer rate', () {
    final repository = OptionalPluginRepository(
      proxyResolver: (_) => 'DIRECT',
      downloadSettings: const OptionalPluginDownloadSettings(),
      proxyAvailable: false,
      manifestLoader: OptionalPluginManifestLoader(
        sourceLoader: () async => '{}',
      ),
      slowCheckWindow: const Duration(seconds: 8),
      minimumBytesPerSecond: 48 * 1024,
    );

    expect(
      repository.isPersistentlySlowForTesting(
        received: 1000,
        elapsed: const Duration(seconds: 7),
        expectedSize: 1000000,
      ),
      isFalse,
    );
    expect(
      repository.isPersistentlySlowForTesting(
        received: 1000,
        elapsed: const Duration(seconds: 9),
        expectedSize: 1000000,
      ),
      isTrue,
    );
    expect(
      repository.isPersistentlySlowForTesting(
        received: 1000000,
        elapsed: const Duration(seconds: 20),
        expectedSize: 1000000,
      ),
      isFalse,
    );
  });
}
