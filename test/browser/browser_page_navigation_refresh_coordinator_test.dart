import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_navigation_refresh_coordinator.dart';

void main() {
  group('BrowserPageNavigationRefreshCoordinator', () {
    test('debounces repeated refresh scheduling', () async {
      final coordinator = BrowserPageNavigationRefreshCoordinator(
        debounceDuration: const Duration(milliseconds: 20),
      );
      var refreshCount = 0;

      coordinator.schedule(
        refresh: () async {
          refreshCount += 1;
        },
      );
      coordinator.schedule(
        refresh: () async {
          refreshCount += 1;
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(refreshCount, 1);
    });

    test('cancel prevents pending refresh', () async {
      final coordinator = BrowserPageNavigationRefreshCoordinator(
        debounceDuration: const Duration(milliseconds: 20),
      );
      var refreshCount = 0;

      coordinator.schedule(
        refresh: () async {
          refreshCount += 1;
        },
      );
      coordinator.cancel();

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(refreshCount, 0);
    });
  });
}
