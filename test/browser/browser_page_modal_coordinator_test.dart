import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/models/browser_tab_session.dart';
import 'package:lightly/browser/services/browser_find_controller.dart';
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
      expect(harness.rebuildCount, 2);
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
              required isFavorited,
              required onToggleFavorite,
              required onToggleProxy,
              required onOpenDownloads,
              required onOpenDataManagement,
              required onCloseTab,
              required onOpenSettings,
              required onEnterFloatingWindowMode,
              required onExitApp,
              required onOpenFavoritesMenu,
              required onFindInPage,
            }) async {
              expect(proxyEnabled, isTrue);
              expect(isFavorited, isFalse);
              onToggleFavorite?.call();
              onFindInPage();
            },
      );

      await coordinator.showMoreActions(
        overlayStateManager: harness.manager,
        context: context,
        proxyEnabled: true,
        isFavorited: false,
        onToggleFavorite: () => calls.add('favorite'),
        onToggleProxy: () {},
        onOpenDownloads: () {},
        onOpenDataManagement: () {},
        onCloseTab: () {},
        onOpenSettings: () {},
        onEnterFloatingWindowMode: () {},
        onExitApp: () {},
        onOpenFavoritesMenu: null,
        onFindInPage: () => calls.add('find'),
      );

      expect(calls, <String>['favorite', 'find']);
      expect(harness.pauseCount, 1);
      expect(harness.lastTrimKeepAlives, isTrue);
      expect(harness.rebuildCount, 2);
      await tester.pump(const Duration(milliseconds: 350));
    });

    testWidgets('showFindInPage tracks overlay without pausing WebView', (
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
        showFindInPageSheet:
            ({required context, required findController}) async {
              presenterCalled = true;
            },
      );

      await coordinator.showFindInPage(
        overlayStateManager: harness.manager,
        context: context,
        findController: BrowserFindController(),
      );

      expect(presenterCalled, isTrue);
      expect(harness.pauseCount, 0);
      expect(harness.rebuildCount, 2);
      expect(harness.manager.shouldFreezeWebView, isTrue);
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
      expect(harness.rebuildCount, 2);
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
  bool? lastTrimKeepAlives;
}
