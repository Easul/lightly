import 'dart:async';

class BrowserPageNavigationRefreshCoordinator {
  BrowserPageNavigationRefreshCoordinator({
    this.debounceDuration = const Duration(milliseconds: 120),
  });

  final Duration debounceDuration;

  Timer? _refreshTimer;
  int _generation = 0;

  void schedule({required Future<void> Function() refresh}) {
    _generation += 1;
    final scheduledGeneration = _generation;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(debounceDuration, () async {
      _refreshTimer = null;
      if (scheduledGeneration != _generation) {
        return;
      }
      await refresh();
    });
  }

  void cancel() {
    _generation += 1;
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }
}
