import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:lightly/browser/services/browser_external_url_launcher_service.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  group('BrowserExternalUrlLauncherService', () {
    test('keeps encoded custom-scheme payload intact when launching', () async {
      const encodedUrl =
          'bankabc://%7B%22method%22%3A%22jumpToSharedProduct%22%2C%22trafficTag%22%3A%2290fc%22%7D';
      Uri? launchedUrl;
      final service = BrowserExternalUrlLauncherService(
        launch: (url, {mode = LaunchMode.platformDefault}) async {
          launchedUrl = url;
          return true;
        },
      );

      final result = await service.launch(
        WebUri(encodedUrl, forceToStringRawValue: true),
      );

      expect(result, BrowserExternalUrlLauncherService.launchedMessage);
      expect(launchedUrl.toString(), encodedUrl);
    });

    test('returns launched message when external app starts', () async {
      final service = BrowserExternalUrlLauncherService(
        launch: (url, {mode = LaunchMode.platformDefault}) async => true,
      );

      final result = await service.launch(Uri.parse('weixin://test'));

      expect(result, BrowserExternalUrlLauncherService.launchedMessage);
    });

    test('returns unavailable message when platform rejects url', () async {
      final service = BrowserExternalUrlLauncherService(
        launch: (url, {mode = LaunchMode.platformDefault}) async => false,
      );

      final result = await service.launch(Uri.parse('alipay://test'));

      expect(result, BrowserExternalUrlLauncherService.unavailableMessage);
    });

    test('returns failed message when launch throws', () async {
      final service = BrowserExternalUrlLauncherService(
        launch: (url, {mode = LaunchMode.platformDefault}) async {
          throw Exception('boom');
        },
      );

      final result = await service.launch(Uri.parse('tg://resolve'));

      expect(result, BrowserExternalUrlLauncherService.failedMessage);
    });
  });
}
