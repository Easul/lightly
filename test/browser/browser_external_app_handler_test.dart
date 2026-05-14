import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_external_app_handler.dart';

void main() {
  group('BrowserExternalAppHandler', () {
    test('returns null for suppressed blocked popup urls', () async {
      final handler = BrowserExternalAppHandler(
        confirmBlockedDialog: (_, __) async => true,
      );

      final status = await handler.handleBlockedByResponse(
        _FakeBuildContext(),
        Uri.parse('data:text/plain,hello'),
        shouldSuppressPopupUrl: (url) => true,
        launchExternalUrl: (_) async => 'opened',
      );

      expect(status, isNull);
    });

    test('returns launch status after confirmation', () async {
      final handler = BrowserExternalAppHandler(
        confirmOpenDialog: (_, __) async => true,
      );

      final status = await handler.confirmAndLaunchExternalUrl(
        _FakeBuildContext(),
        Uri.parse('intent://example'),
        launchExternalUrl: (_) async => '已尝试打开外部应用',
      );

      expect(status, '已尝试打开外部应用');
      expect(handler.isShowingExternalAppDialog, isFalse);
    });

    test('returns null when external open is cancelled', () async {
      final handler = BrowserExternalAppHandler(
        confirmOpenDialog: (_, __) async => false,
      );

      final status = await handler.confirmAndLaunchExternalUrl(
        _FakeBuildContext(),
        Uri.parse('intent://example'),
        launchExternalUrl: (_) async => 'should-not-run',
      );

      expect(status, isNull);
      expect(handler.isShowingExternalAppDialog, isFalse);
    });
  });
}

class _FakeBuildContext extends Fake implements BuildContext {}
