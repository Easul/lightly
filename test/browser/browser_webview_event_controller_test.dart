import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_webview_event_controller.dart';

void main() {
  group('BrowserWebViewEventController', () {
    const controller = BrowserWebViewEventController();

    test('limits load-state rebuild decisions to active tab changes', () {
      expect(
        controller.shouldClearStatusOnLoadStart(
          isActiveTab: true,
          currentStatusMessage: 'message',
          didChangeProgress: false,
          didChangeLoading: false,
        ),
        isTrue,
      );
      expect(
        controller.shouldClearStatusOnLoadStart(
          isActiveTab: false,
          currentStatusMessage: 'message',
          didChangeProgress: true,
          didChangeLoading: true,
        ),
        isFalse,
      );
      expect(
        controller.shouldRebuildOnLoadStop(
          isActiveTab: true,
          didChangeProgress: true,
          didChangeLoading: false,
        ),
        isTrue,
      );
      expect(
        controller.shouldRebuildOnLoadStop(
          isActiveTab: false,
          didChangeProgress: true,
          didChangeLoading: true,
        ),
        isFalse,
      );
    });

    test('ends loading before routing blocked-response errors', () async {
      final events = <String>[];

      controller.handleError(
        hostedTabId: 'tab-1',
        isMounted: true,
        isActiveTab: true,
        requestedUrl: Uri.parse('https://example.com/popup'),
        description: 'net::ERR_BLOCKED_BY_RESPONSE',
        blockedPopupStatus: 'blocked',
        externalSchemeStatus: 'external',
        requestedUrlIsWebScheme: true,
        endRefreshing: () => events.add('refresh-ended'),
        markTabNotLoading: (tabId) => events.add('not-loading:$tabId'),
        handleBlockedByResponse: (_) async => events.add('blocked-handler'),
        confirmExternalUrl: (_) async => events.add('external-handler'),
        setStatus: (status) => events.add('status:$status'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, <String>[
        'refresh-ended',
        'not-loading:tab-1',
        'blocked-handler',
        'status:blocked',
      ]);
    });

    test(
      'routes unknown external schemes without handling web schemes',
      () async {
        final externalEvents = <String>[];
        final webEvents = <String>[];

        void run({
          required Uri url,
          required bool isWebScheme,
          required List<String> events,
        }) {
          controller.handleError(
            hostedTabId: 'tab-1',
            isMounted: true,
            isActiveTab: true,
            requestedUrl: url,
            description: 'net::ERR_UNKNOWN_URL_SCHEME',
            blockedPopupStatus: 'blocked',
            externalSchemeStatus: 'external',
            requestedUrlIsWebScheme: isWebScheme,
            endRefreshing: () {},
            markTabNotLoading: (_) {},
            handleBlockedByResponse: (_) async {},
            confirmExternalUrl: (_) async => events.add('external-handler'),
            setStatus: (status) => events.add('status:$status'),
          );
        }

        run(
          url: Uri.parse('bankabc://payload'),
          isWebScheme: false,
          events: externalEvents,
        );
        run(
          url: Uri.parse('https://example.com'),
          isWebScheme: true,
          events: webEvents,
        );
        await Future<void>.delayed(Duration.zero);

        expect(externalEvents, <String>['external-handler', 'status:external']);
        expect(webEvents, <String>['status:external']);
      },
    );

    test('background errors stop loading without changing active status', () {
      final events = <String>[];

      controller.handleError(
        hostedTabId: 'tab-2',
        isMounted: true,
        isActiveTab: false,
        requestedUrl: Uri.parse('https://example.com'),
        description: 'background error',
        blockedPopupStatus: 'blocked',
        externalSchemeStatus: 'external',
        requestedUrlIsWebScheme: true,
        endRefreshing: () => events.add('refresh-ended'),
        markTabNotLoading: (tabId) => events.add('not-loading:$tabId'),
        handleBlockedByResponse: (_) async => events.add('blocked-handler'),
        confirmExternalUrl: (_) async => events.add('external-handler'),
        setStatus: (status) => events.add('status:$status'),
      );

      expect(events, <String>['refresh-ended', 'not-loading:tab-2']);
    });

    test(
      'active history schedules refresh and background history syncs URL',
      () async {
        final events = <String>[];

        controller.handleVisitedHistory(
          hostedTabId: 'active',
          isFavoritesPage: false,
          isActiveTab: true,
          url: Uri.parse('https://example.com/active'),
          isWebScheme: true,
          recordCookieOrigin: () async => events.add('cookie'),
          scheduleActiveRefresh: () => events.add('schedule'),
          updateBackgroundTabUrl: (_, _) => events.add('background'),
        );
        controller.handleVisitedHistory(
          hostedTabId: 'background',
          isFavoritesPage: false,
          isActiveTab: false,
          url: Uri.parse('https://example.com/background'),
          isWebScheme: true,
          recordCookieOrigin: () async => events.add('background-cookie'),
          scheduleActiveRefresh: () => events.add('background-schedule'),
          updateBackgroundTabUrl: (tabId, url) =>
              events.add('background:$tabId:$url'),
        );
        await Future<void>.delayed(Duration.zero);

        expect(events, <String>[
          'cookie',
          'schedule',
          'background:background:https://example.com/background',
        ]);
      },
    );
  });
}
