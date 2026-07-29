import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/app/optional_feature_coordinator.dart';
import 'package:lightly/features/optional_plugins/domain/optional_plugin_manifest.dart';
import 'package:lightly/features/optional_plugins/infrastructure/optional_plugin_download_settings_store.dart';
import 'package:lightly/pages/optional_plugin_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('plugin settings fits a narrow phone and shows pinned releases', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      MaterialApp(
        home: OptionalPluginSettingsPage(
          settingsStore: OptionalPluginDownloadSettingsStore(
            preferences: preferences,
          ),
          coordinator: _FakeOptionalFeatureCoordinator(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('插件下载'), findsOneWidget);
    expect(find.text('自动'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('镜像'), findsOneWidget);
    expect(find.text('TG 工具插件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeOptionalFeatureCoordinator extends OptionalFeatureCoordinator {
  @override
  Future<OptionalPluginManifest> loadBundledManifest() async {
    return OptionalPluginManifest.parse('''
      {
        "schemaVersion": 1,
        "plugins": {
          "telegram": {
            "packageName": "lightly.tool.plugin.telegram",
            "apiVersion": 3,
            "versionCode": 1,
            "versionName": "v1",
            "minimumLightlyVersionCode": 1,
            "artifacts": {
              "arm64-v8a": {
                "url": "https://github.com/Easul/lightly-plugins/releases/download/v1/telegram.apk",
                "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "size": 1
              }
            }
          }
        }
      }
    ''');
  }
}
