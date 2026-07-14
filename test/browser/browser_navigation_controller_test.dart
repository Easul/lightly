import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_navigation_controller.dart';

void main() {
  group('BrowserNavigationController', () {
    const controller = BrowserNavigationController();

    test('allows a missing navigation URL without side effects', () async {
      var synced = false;
      var confirmed = false;

      final policy = await controller.handleNavigationRequest(
        requestedUrl: null,
        isExternalDialogShowing: false,
        syncUrl: (_) => synced = true,
        confirmExternalUrl: (_) async => confirmed = true,
      );

      expect(policy, NavigationActionPolicy.ALLOW);
      expect(synced, isFalse);
      expect(confirmed, isFalse);
    });

    test('syncs web navigation before allowing it', () async {
      final events = <String>[];
      final requestedUrl = Uri.parse('https://example.com/path');

      final policy = await controller.handleNavigationRequest(
        requestedUrl: requestedUrl,
        isExternalDialogShowing: false,
        syncUrl: (url) => events.add('sync:$url'),
        confirmExternalUrl: (_) async => events.add('confirm'),
      );

      expect(policy, NavigationActionPolicy.ALLOW);
      expect(events, <String>['sync:https://example.com/path']);
    });

    test('keeps file and content navigation inside WebView', () async {
      final syncedUrls = <String>[];

      for (final requestedUrl in <Uri>[
        Uri.parse('file:///storage/emulated/0/Download/example.html'),
        Uri.parse('content://lightly.tool/imported/example.pdf'),
      ]) {
        final policy = await controller.handleNavigationRequest(
          requestedUrl: requestedUrl,
          isExternalDialogShowing: false,
          syncUrl: syncedUrls.add,
          confirmExternalUrl: (_) async => fail('must remain internal'),
        );
        expect(policy, NavigationActionPolicy.ALLOW);
      }

      expect(syncedUrls, <String>[
        'file:///storage/emulated/0/Download/example.html',
        'content://lightly.tool/imported/example.pdf',
      ]);
    });

    test(
      'cancels duplicate external navigation while dialog is open',
      () async {
        var confirmed = false;

        final policy = await controller.handleNavigationRequest(
          requestedUrl: Uri.parse('bankabc://payload'),
          isExternalDialogShowing: true,
          syncUrl: (_) {},
          confirmExternalUrl: (_) async => confirmed = true,
        );

        expect(policy, NavigationActionPolicy.CANCEL);
        expect(confirmed, isFalse);
      },
    );

    test(
      'confirms external navigation before canceling WebView load',
      () async {
        final events = <String>[];

        final policy = await controller.handleNavigationRequest(
          requestedUrl: Uri.parse('bankabc://payload'),
          isExternalDialogShowing: false,
          syncUrl: (_) => events.add('sync'),
          confirmExternalUrl: (_) async => events.add('confirm'),
        );

        expect(policy, NavigationActionPolicy.CANCEL);
        expect(events, <String>['confirm']);
      },
    );

    test('syncs and refreshes web history updates in order', () async {
      final events = <String>[];

      await controller.handleVisitedHistoryUpdate(
        requestedUrl: Uri.parse('https://example.com/next'),
        shouldHandle: true,
        syncUrl: (url) => events.add('sync:$url'),
        refreshNavigation: () async => events.add('refresh'),
        confirmExternalUrl: (_) async => events.add('confirm'),
      );

      expect(events, <String>['sync:https://example.com/next', 'refresh']);
    });

    test('ignores duplicate history updates', () async {
      final events = <String>[];

      await controller.handleVisitedHistoryUpdate(
        requestedUrl: Uri.parse('https://example.com'),
        shouldHandle: false,
        syncUrl: (_) => events.add('sync'),
        refreshNavigation: () async => events.add('refresh'),
        confirmExternalUrl: (_) async => events.add('confirm'),
      );

      expect(events, isEmpty);
    });

    test(
      'dispatches external history updates without blocking refresh flow',
      () async {
        final events = <String>[];

        await controller.handleVisitedHistoryUpdate(
          requestedUrl: Uri.parse('bankabc://payload'),
          shouldHandle: true,
          syncUrl: (_) => events.add('sync'),
          refreshNavigation: () async => events.add('refresh'),
          confirmExternalUrl: (_) async => events.add('confirm'),
        );
        await Future<void>.delayed(Duration.zero);

        expect(events, <String>['confirm']);
      },
    );
  });
}
