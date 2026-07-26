import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_external_app_handler.dart';
import 'package:lightly/browser/services/browser_external_url_launcher_service.dart';
import 'package:lightly/browser/services/browser_page_navigation_facade.dart';
import 'package:lightly/browser/services/browser_popup_raw_url_resolver.dart';
import 'package:lightly/browser/services/browser_popup_window_handler.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  group('BrowserPageNavigationFacade', () {
    test('resolves captured popup url before deciding its route', () async {
      const rawUrl =
          'bankabc://%7B%22method%22%3A%22jumpToSharedProduct%22%2C%22trafficTag%22%3A%2290fc%22%7D';
      final facade = BrowserPageNavigationFacade(
        popupRawUrlResolver: BrowserPopupRawUrlResolver(
          logWriter: (_) async {},
          debugLoggingEnabled: false,
        ),
      );
      facade.recordCapturedPopupUrl(rawUrl);

      final decision = await facade.resolvePopupWindow(
        fallbackUrl: rawUrl.toLowerCase(),
        sourceUrl: 'https://example.com',
        hasGesture: true,
        openNewWindowInTab: false,
        evaluateJavascript: (_) async => null,
      );

      expect(decision.action, BrowserPopupWindowAction.external);
      expect(decision.externalUrl, rawUrl);
    });

    test('confirms and launches external urls through one boundary', () async {
      const rawUrl =
          'bankabc://%7B%22method%22%3A%22jumpToSharedProduct%22%2C%22trafficTag%22%3A%2290fc%22%7D';
      Uri? launchedUrl;
      final facade = BrowserPageNavigationFacade(
        externalAppHandler: BrowserExternalAppHandler(
          confirmOpenDialog: (_, _) async => true,
        ),
        externalUrlLauncher: BrowserExternalUrlLauncherService(
          launch: (url, {mode = LaunchMode.platformDefault}) async {
            launchedUrl = url;
            return true;
          },
        ),
      );

      final status = await facade.confirmAndLaunchExternalUrl(
        _FakeBuildContext(),
        WebUri(rawUrl, forceToStringRawValue: true),
      );

      expect(status, BrowserExternalUrlLauncherService.launchedMessage);
      expect(launchedUrl.toString(), rawUrl);
    });

    test(
      'suppresses duplicate external navigation during confirmation',
      () async {
        final confirmation = Completer<bool>();
        final facade = BrowserPageNavigationFacade(
          externalAppHandler: BrowserExternalAppHandler(
            confirmOpenDialog: (_, _) => confirmation.future,
          ),
        );
        final pendingConfirmation = facade.confirmAndLaunchExternalUrl(
          _FakeBuildContext(),
          Uri.parse('bankabc://first'),
        );
        await Future<void>.delayed(Duration.zero);
        var duplicateConfirmed = false;

        final policy = await facade.handleNavigationRequest(
          requestedUrl: Uri.parse('bankabc://second'),
          syncUrl: (_) {},
          confirmExternalUrl: (_) async => duplicateConfirmed = true,
        );

        expect(policy, NavigationActionPolicy.CANCEL);
        expect(duplicateConfirmed, isFalse);
        confirmation.complete(false);
        await pendingConfirmation;
      },
    );
  });
}

class _FakeBuildContext extends Fake implements BuildContext {}
