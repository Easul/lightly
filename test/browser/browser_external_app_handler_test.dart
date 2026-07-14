import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_external_app_handler.dart';

void main() {
  group('BrowserExternalAppHandler', () {
    testWidgets('shows decoded custom-scheme payload in confirmation dialog', (
      tester,
    ) async {
      final handler = BrowserExternalAppHandler();
      const encodedUrl =
          'bankabc://%7B%22method%22%3A%22jumptosharedproduct%22%2C%22type%22%3A%221%22%7D';

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => handler.confirmAndLaunchExternalUrl(
                context,
                Uri.parse(encodedUrl),
                launchExternalUrl: (_) async => 'opened',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'bankabc://{"method":"jumptosharedproduct","type":"1"}',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('%7B%22method%22'), findsNothing);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });

    test('returns null for suppressed blocked popup urls', () async {
      final handler = BrowserExternalAppHandler(
        confirmBlockedDialog: (_, _) async => true,
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
        confirmOpenDialog: (_, _) async => true,
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
        confirmOpenDialog: (_, _) async => false,
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
