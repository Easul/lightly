import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/optional_plugins/domain/optional_feature.dart';
import 'package:lightly/features/optional_plugins/domain/optional_plugin_manifest.dart';

void main() {
  test('parses ABI-specific plugin artifacts', () {
    final manifest = OptionalPluginManifest.parse('''
      {
        "schemaVersion": 1,
        "plugins": {
          "telegram": {
            "packageName": "lightly.tool.plugin.telegram",
            "apiVersion": 1,
            "versionCode": 12,
            "versionName": "1.2.0",
            "minimumLightlyVersionCode": 5000,
            "artifacts": {
              "arm64-v8a": {
                "url": "https://github.com/Easul/lightly-plugins/releases/download/v1/telegram.apk",
                "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "size": 1234
              }
            }
          }
        }
      }
    ''');

    final release = manifest.releaseFor(OptionalFeatureId.telegram)!;
    expect(release.versionCode, 12);
    expect(release.artifactForAbi('arm64-v8a')?.size, 1234);
    expect(release.artifactForAbi('armeabi-v7a'), isNull);
  });

  test('rejects non-https artifact URLs', () {
    expect(
      () => OptionalPluginManifest.parse('''
        {
          "schemaVersion": 1,
          "plugins": {
            "telegram": {
              "packageName": "lightly.tool.plugin.telegram",
              "apiVersion": 1,
              "versionCode": 1,
              "versionName": "1",
              "minimumLightlyVersionCode": 1,
              "artifacts": {
                "arm64-v8a": {
                  "url": "http://example.com/plugin.apk",
                  "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                  "size": 10
                }
              }
            }
          }
        }
      '''),
      throwsFormatException,
    );
  });
}
