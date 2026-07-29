import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/optional_plugins/domain/optional_feature.dart';
import 'package:lightly/features/optional_plugins/domain/optional_plugin_download_settings.dart';
import 'package:lightly/features/optional_plugins/domain/optional_plugin_manifest.dart';
import 'package:lightly/features/optional_plugins/infrastructure/optional_plugin_manifest_loader.dart';
import 'package:lightly/features/optional_plugins/infrastructure/optional_plugin_repository.dart';

void main() {
  test(
    'automatic download falls back after a retryable primary error',
    () async {
      final primary = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final mirror = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bytes = <int>[1, 2, 3, 4, 5];
      var primaryHits = 0;
      var mirrorHits = 0;
      primary.listen((request) async {
        primaryHits++;
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
      });
      mirror.listen((request) async {
        mirrorHits++;
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      });
      final temp = await Directory.systemTemp.createTemp(
        'optional_plugin_repository_test_',
      );
      addTearDown(() async {
        await primary.close(force: true);
        await mirror.close(force: true);
        await temp.delete(recursive: true);
      });

      final repository = OptionalPluginRepository(
        proxyResolver: (_) => 'DIRECT',
        downloadSettings: const OptionalPluginDownloadSettings(),
        proxyAvailable: false,
        manifestLoader: OptionalPluginManifestLoader(
          sourceLoader: () async => '{}',
        ),
        planner: _FixedAttemptPlanner(
          primary: Uri.parse('http://127.0.0.1:${primary.port}/plugin.apk'),
          mirror: Uri.parse('http://127.0.0.1:${mirror.port}/plugin.apk'),
        ),
        temporaryDirectory: () async => temp,
        allowInsecureLocalhostForTesting: true,
      );
      final artifact = OptionalPluginArtifact(
        url: Uri.parse('https://github.com/example/plugin.apk'),
        sha256: sha256.convert(bytes).toString(),
        size: bytes.length,
      );
      const release = OptionalPluginRelease(
        featureId: OptionalFeatureId.telegram,
        packageName: 'lightly.tool.plugin.telegram',
        apiVersion: 3,
        versionCode: 1,
        versionName: '1',
        minimumLightlyVersionCode: 1,
        artifacts: <String, OptionalPluginArtifact>{},
      );

      final file = await repository.downloadArtifact(
        OptionalFeatureCatalog.descriptor(OptionalFeatureId.telegram),
        release,
        artifact,
      );

      expect(await file.readAsBytes(), bytes);
      expect(primaryHits, 1);
      expect(mirrorHits, 1);
    },
  );

  test(
    'automatic download falls back when an error response body stalls',
    () async {
      final primary = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final mirror = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bytes = <int>[6, 7, 8];
      primary.listen((request) async {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write('partial');
        await request.response.flush();
      });
      mirror.listen((request) async {
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      });
      final temp = await Directory.systemTemp.createTemp(
        'optional_plugin_stalled_response_test_',
      );
      addTearDown(() async {
        await primary.close(force: true);
        await mirror.close(force: true);
        await temp.delete(recursive: true);
      });
      final repository = _createRepository(
        primary: Uri.parse('http://127.0.0.1:${primary.port}/plugin.apk'),
        mirror: Uri.parse('http://127.0.0.1:${mirror.port}/plugin.apk'),
        temporaryDirectory: temp,
        idleTimeout: const Duration(milliseconds: 100),
      );

      final file = await repository.downloadArtifact(
        OptionalFeatureCatalog.descriptor(OptionalFeatureId.telegram),
        _release,
        OptionalPluginArtifact(
          url: Uri.parse('https://github.com/example/plugin.apk'),
          sha256: sha256.convert(bytes).toString(),
          size: bytes.length,
        ),
      );

      expect(await file.readAsBytes(), bytes);
    },
  );

  test('hash mismatch is not mirrored and removes the temporary APK', () async {
    final primary = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mirror = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var mirrorHits = 0;
    primary.listen((request) async {
      request.response.contentLength = 3;
      request.response.add(<int>[1, 2, 3]);
      await request.response.close();
    });
    mirror.listen((request) async {
      mirrorHits++;
      request.response.contentLength = 3;
      request.response.add(<int>[4, 5, 6]);
      await request.response.close();
    });
    final temp = await Directory.systemTemp.createTemp(
      'optional_plugin_hash_mismatch_test_',
    );
    addTearDown(() async {
      await primary.close(force: true);
      await mirror.close(force: true);
      await temp.delete(recursive: true);
    });
    final repository = _createRepository(
      primary: Uri.parse('http://127.0.0.1:${primary.port}/plugin.apk'),
      mirror: Uri.parse('http://127.0.0.1:${mirror.port}/plugin.apk'),
      temporaryDirectory: temp,
    );

    await expectLater(
      repository.downloadArtifact(
        OptionalFeatureCatalog.descriptor(OptionalFeatureId.telegram),
        _release,
        OptionalPluginArtifact(
          url: Uri.parse('https://github.com/example/plugin.apk'),
          sha256: sha256.convert(<int>[9, 9, 9]).toString(),
          size: 3,
        ),
      ),
      throwsA(
        isA<OptionalPluginRepositoryException>().having(
          (error) => error.retryable,
          'retryable',
          isFalse,
        ),
      ),
    );

    expect(mirrorHits, 0);
    expect(
      File(
        '${temp.path}/optional_plugins/telegram-${_release.versionCode}.apk',
      ).existsSync(),
      isFalse,
    );
  });
}

const _release = OptionalPluginRelease(
  featureId: OptionalFeatureId.telegram,
  packageName: 'lightly.tool.plugin.telegram',
  apiVersion: 3,
  versionCode: 1,
  versionName: '1',
  minimumLightlyVersionCode: 1,
  artifacts: <String, OptionalPluginArtifact>{},
);

OptionalPluginRepository _createRepository({
  required Uri primary,
  required Uri mirror,
  required Directory temporaryDirectory,
  Duration idleTimeout = const Duration(seconds: 10),
}) {
  return OptionalPluginRepository(
    proxyResolver: (_) => 'DIRECT',
    downloadSettings: const OptionalPluginDownloadSettings(),
    proxyAvailable: false,
    manifestLoader: OptionalPluginManifestLoader(
      sourceLoader: () async => '{}',
    ),
    planner: _FixedAttemptPlanner(primary: primary, mirror: mirror),
    temporaryDirectory: () async => temporaryDirectory,
    idleTimeout: idleTimeout,
    allowInsecureLocalhostForTesting: true,
  );
}

class _FixedAttemptPlanner extends OptionalPluginDownloadPlanner {
  const _FixedAttemptPlanner({required this.primary, required this.mirror});

  final Uri primary;
  final Uri mirror;

  @override
  List<OptionalPluginDownloadAttempt> plan({
    required Uri source,
    required OptionalPluginDownloadSettings settings,
    required bool proxyAvailable,
  }) {
    return <OptionalPluginDownloadAttempt>[
      OptionalPluginDownloadAttempt(
        uri: primary,
        useProxy: false,
        label: 'primary',
      ),
      OptionalPluginDownloadAttempt(
        uri: mirror,
        useProxy: false,
        label: 'mirror',
        mirrorHost: mirror.host,
      ),
    ];
  }
}
