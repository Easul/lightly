import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_overlay_load_freeze_coordinator.dart';

void main() {
  group('BrowserPageOverlayLoadFreezeCoordinator', () {
    late _OverlayLoadFreezeHarness harness;

    setUp(() {
      harness = _OverlayLoadFreezeHarness();
    });

    tearDown(() {
      harness.coordinator.cancel();
    });

    test('does not stop loading before freeze delay elapses', () async {
      harness.schedule();

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(harness.stopCount, 0);
    });

    test('stops active loading when overlay stays open past delay', () async {
      harness.schedule();

      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(harness.stopCount, 1);
    });

    test('cancels pending freeze when overlay closes quickly', () async {
      harness.schedule();
      harness.overlayOpen = false;
      harness.coordinator.resume(
        isMounted: () => harness.mounted,
        activeTabId: () => harness.activeTabId,
        currentUrl: () => harness.url,
        isFavoritesPage: harness.isFavoritesPage,
        reload: harness.reload,
      );

      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(harness.stopCount, 0);
      expect(harness.reloads, isEmpty);
    });

    test('reloads stopped url after overlay resume', () async {
      harness.schedule();
      await Future<void>.delayed(const Duration(milliseconds: 70));

      harness.overlayOpen = false;
      harness.coordinator.resume(
        isMounted: () => harness.mounted,
        activeTabId: () => harness.activeTabId,
        currentUrl: () => harness.url,
        isFavoritesPage: harness.isFavoritesPage,
        reload: harness.reload,
      );

      expect(harness.reloads, ['https://example.com']);
    });

    test('does not reload if active tab changed after stopped load', () async {
      harness.schedule();
      await Future<void>.delayed(const Duration(milliseconds: 70));

      harness.activeTabId = 'tab-2';
      harness.overlayOpen = false;
      harness.coordinator.resume(
        isMounted: () => harness.mounted,
        activeTabId: () => harness.activeTabId,
        currentUrl: () => harness.url,
        isFavoritesPage: harness.isFavoritesPage,
        reload: harness.reload,
      );

      expect(harness.reloads, isEmpty);
    });

    test('does not stop favorites page loads', () async {
      harness.url = 'lightly://favorites';
      harness.schedule();

      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(harness.stopCount, 0);
    });
  });
}

class _OverlayLoadFreezeHarness {
  final BrowserPageOverlayLoadFreezeCoordinator coordinator =
      BrowserPageOverlayLoadFreezeCoordinator(
        freezeDelay: const Duration(milliseconds: 50),
      );

  bool mounted = true;
  bool overlayOpen = true;
  bool loading = true;
  String? activeTabId = 'tab-1';
  String url = 'https://example.com';
  int stopCount = 0;
  final List<String> reloads = <String>[];

  void schedule() {
    coordinator.schedule(
      isMounted: () => mounted,
      hasOpenOverlay: () => overlayOpen,
      activeTabId: () => activeTabId,
      currentUrl: () => url,
      isLoading: () => loading,
      isFavoritesPage: isFavoritesPage,
      stopLoading: stopLoading,
    );
  }

  bool isFavoritesPage(String url) => url == 'lightly://favorites';

  void stopLoading() {
    stopCount++;
    loading = false;
  }

  void reload(String url) {
    reloads.add(url);
  }
}
