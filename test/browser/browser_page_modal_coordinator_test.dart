import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/models/browser_tab_session.dart';
import 'package:lightly/pages/browser_page_lifecycle_coordinator.dart';
import 'package:lightly/pages/browser_page_modal_coordinator.dart';
import 'package:lightly/pages/browser_page_overlay_state_manager.dart';

void main() {
  group('BrowserPageModalCoordinator', () {
    late _OverlayHarness harness;
    late BuildContext context;

    setUp(() {
      harness = _OverlayHarness();
    });

    tearDown(() {
      harness.manager.dispose();
    });

    testWidgets('showTabSwitcher wraps overlay without trimming keepalives', (
      tester,
    ) async {
      await tester.pumpWidget(
        _Host(
          onBuild: (buildContext) {
            context = buildContext;
          },
        ),
      );
      var presenterCalled = false;
      final coordinator = BrowserPageModalCoordinator(
        showTabSwitcherModal:
            ({
              required context,
              required tabs,
              required activeTabId,
              required onSelectTab,
              required onCloseTab,
              required onCloseAll,
              required onNewTab,
            }) async {
              presenterCalled = true;
              expect(tabs, isEmpty);
              expect(activeTabId, isNull);
            },
      );

      await coordinator.showTabSwitcher(
        overlayStateManager: harness.manager,
        context: context,
        tabs: const <BrowserTabSession>[],
        activeTabId: null,
        onSelectTab: (_) {},
        onCloseTab: (_) {},
        onCloseAll: () {},
        onNewTab: () {},
      );

      expect(presenterCalled, isTrue);
      expect(harness.pauseCount, 1);
      expect(harness.lastTrimKeepAlives, isFalse);
      expect(harness.overlayRefreshCount, 1);
      expect(harness.rebuildCount, 0);
      expect(harness.manager.shouldFreezeWebView, isTrue);
      await tester.pump(const Duration(milliseconds: 350));
    });

    testWidgets('showMoreActions wraps overlay and forwards callbacks', (
      tester,
    ) async {
      await tester.pumpWidget(
        _Host(
          onBuild: (buildContext) {
            context = buildContext;
          },
        ),
      );
      final calls = <String>[];
      final coordinator = BrowserPageModalCoordinator(
        showMoreActionsModal:
            ({
              required context,
              required proxyEnabled,
              required desktopModeEnabled,
              required webDebugConsoleEnabled,
              required isFavorited,
              required onToggleFavorite,
              required onToggleProxy,
              required onToggleWebDebugConsole,
              required onToggleDesktopMode,
              required onOpenDownloads,
              required onOpenTools,
              required onCloseTab,
              required onOpenSettings,
              required onEnterFloatingWindowMode,
              required onExitApp,
              required onOpenFavoritesMenu,
            }) async {
              expect(proxyEnabled, isTrue);
              expect(desktopModeEnabled, isTrue);
              expect(webDebugConsoleEnabled, isTrue);
              expect(isFavorited, isFalse);
              onToggleFavorite?.call();
              onToggleWebDebugConsole();
              onToggleDesktopMode();
            },
      );

      await coordinator.showMoreActions(
        overlayStateManager: harness.manager,
        context: context,
        proxyEnabled: true,
        desktopModeEnabled: true,
        webDebugConsoleEnabled: true,
        isFavorited: false,
        onToggleFavorite: () => calls.add('favorite'),
        onToggleProxy: () {},
        onToggleWebDebugConsole: () => calls.add('debug'),
        onToggleDesktopMode: () => calls.add('desktop'),
        onOpenDownloads: () {},
        onOpenTools: () {},
        onCloseTab: () {},
        onOpenSettings: () {},
        onEnterFloatingWindowMode: () {},
        onExitApp: () {},
        onOpenFavoritesMenu: null,
      );

      expect(calls, <String>['favorite', 'debug', 'desktop']);
      expect(harness.pauseCount, 1);
      expect(harness.lastTrimKeepAlives, isTrue);
      expect(harness.overlayRefreshCount, 1);
      expect(harness.rebuildCount, 0);
      await tester.pump(const Duration(milliseconds: 350));
    });

    testWidgets('showFavoritesMenu closes overlay when presenter throws', (
      tester,
    ) async {
      await tester.pumpWidget(
        _Host(
          onBuild: (buildContext) {
            context = buildContext;
          },
        ),
      );
      final coordinator = BrowserPageModalCoordinator(
        showFavoritesMenuSheet:
            ({
              required context,
              required onAddFavorite,
              required onToggleReorderMode,
            }) async {
              throw StateError('boom');
            },
      );

      await expectLater(
        coordinator.showFavoritesMenu(
          overlayStateManager: harness.manager,
          context: context,
          onAddFavorite: () {},
          onToggleReorderMode: () {},
        ),
        throwsA(isA<StateError>()),
      );

      expect(harness.pauseCount, 1);
      expect(harness.overlayRefreshCount, 1);
      expect(harness.rebuildCount, 0);
      await tester.pump(const Duration(milliseconds: 350));
    });
  });
}

class _Host extends StatelessWidget {
  const _Host({required this.onBuild});

  final ValueChanged<BuildContext> onBuild;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          onBuild(context);
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _OverlayHarness {
  _OverlayHarness() {
    manager = BrowserPageOverlayStateManager(
      coordinator: const BrowserPageLifecycleCoordinator(),
      isMounted: () => true,
      syncNotifiers: () {},
      rebuild: () => rebuildCount++,
      refreshOverlayState: () => overlayRefreshCount++,
      pauseWebView: ({required trimKeepAlives}) {
        pauseCount++;
        lastTrimKeepAlives = trimKeepAlives;
      },
      resumeWebView: () => resumeCount++,
    );
  }

  late final BrowserPageOverlayStateManager manager;
  int pauseCount = 0;
  int resumeCount = 0;
  int rebuildCount = 0;
  int overlayRefreshCount = 0;
  bool? lastTrimKeepAlives;
}
