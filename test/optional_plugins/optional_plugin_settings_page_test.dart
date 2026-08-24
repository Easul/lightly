import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/app/optional_feature_coordinator.dart';
import 'package:lightly/features/optional_plugins/domain/optional_plugin_manifest.dart';
import 'package:lightly/features/optional_plugins/infrastructure/optional_plugin_download_settings_store.dart';
import 'package:lightly/features/tools/tool_visibility_store.dart';
import 'package:lightly/pages/optional_plugin_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('plugin settings only shows releases for enabled tools', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{
      ToolVisibilityStore.storageKey:
          '["remote_control","p2p_vpn","life_runtime"]',
    });
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
    expect(find.text('远程语音插件'), findsNothing);
    expect(find.text('EasyTier 插件'), findsNothing);
    expect(find.text('人生知识库运行时'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plugin settings has an empty state when tools stay hidden', (
    tester,
  ) async {
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

    expect(find.text('暂无已启用的可选插件'), findsOneWidget);
    expect(find.text('TG 工具插件'), findsNothing);
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
