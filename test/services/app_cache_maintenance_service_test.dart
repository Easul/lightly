import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/services/app_cache_maintenance_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppCacheMaintenanceService', () {
    late Directory tempDirectory;
    late Directory cacheDirectory;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDirectory = await Directory.systemTemp.createTemp('lightly-temp-');
      cacheDirectory = await Directory.systemTemp.createTemp('lightly-cache-');
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
      if (await cacheDirectory.exists()) {
        await cacheDirectory.delete(recursive: true);
      }
    });

    AppCacheMaintenanceService buildService({int Function()? onClearWebView}) {
      return AppCacheMaintenanceService(
        getTemporaryDirectoryFn: () async => tempDirectory,
        getApplicationCacheDirectoryFn: () async => cacheDirectory,
        clearWebViewCacheFn: () async {
          onClearWebView?.call();
        },
      );
    }

    Future<void> seedCacheFiles() async {
      await File('${tempDirectory.path}/temp.txt').writeAsString('temp');
      await Directory('${cacheDirectory.path}/nested').create(recursive: true);
      await File(
        '${cacheDirectory.path}/nested/cache.txt',
      ).writeAsString('cache');
    }

    test(
      'clearAppCache removes cached children and records timestamp',
      () async {
        var webViewCleared = 0;
        final service = buildService(onClearWebView: () => webViewCleared++);
        await seedCacheFiles();

        final result = await service.clearAppCache();
        final prefs = await SharedPreferences.getInstance();

        expect(result.clearedEntries, 2);
        expect(result.clearedDirectoryPaths, hasLength(2));
        expect(await tempDirectory.list().isEmpty, isTrue);
        expect(await cacheDirectory.list().isEmpty, isTrue);
        expect(webViewCleared, 1);
        expect(prefs.getInt('app_cache_last_cleanup_at_ms'), isNotNull);
      },
    );

    test('maybeAutoClear respects configured interval', () async {
      final service = buildService();
      await seedCacheFiles();
      final settings = BrowserSettings.defaults().copyWith(
        appCacheAutoClearEnabled: true,
        appCacheAutoClearIntervalHours: 24,
      );

      final firstRun = await service.maybeAutoClear(settings);
      final secondRun = await service.maybeAutoClear(settings);

      expect(firstRun, isTrue);
      expect(secondRun, isFalse);
    });
  });
}
