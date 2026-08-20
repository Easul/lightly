import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/optional_plugins/domain/optional_feature.dart';
import 'package:lightly/features/optional_plugins/domain/optional_plugin_status.dart';

void main() {
  test('catalog keeps stable package and API contracts', () {
    final telegram = OptionalFeatureCatalog.descriptor(
      OptionalFeatureId.telegram,
    );

    expect(telegram.packageName, 'lightly.tool.plugin.telegram');
    expect(telegram.minimumApiVersion, 3);
    expect(
      OptionalFeatureCatalog.descriptor(
        OptionalFeatureId.webRtcVoice,
      ).minimumApiVersion,
      3,
    );
    expect(
      OptionalFeatureCatalog.descriptor(
        OptionalFeatureId.lifeRuntime,
      ).packageName,
      'lightly.tool.plugin.liferuntime',
    );
    expect(
      OptionalFeatureCatalog.descriptor(
        OptionalFeatureId.lifeRuntime,
      ).minimumApiVersion,
      3,
    );
    expect(OptionalFeatureCatalog.manifestAsset, endsWith('plugins.json'));
  });

  test('status requires install trust enablement and compatible API', () {
    const status = OptionalPluginStatus(
      installed: true,
      trusted: true,
      enabled: true,
      apiVersion: 2,
    );

    expect(status.supportsApi(1), isTrue);
    expect(status.supportsApi(3), isFalse);
  });

  test('maps platform status without trusting missing values', () {
    final status = OptionalPluginStatus.fromMap(<Object?, Object?>{
      'installed': true,
      'versionCode': 12,
    });

    expect(status.installed, isTrue);
    expect(status.trusted, isFalse);
    expect(status.supportsApi(1), isFalse);
  });
}
