typedef BrowserWebViewAvailabilityCheck = bool Function();
typedef BrowserWebViewBoolReader = Future<bool> Function();
typedef BrowserWebViewTitleReader = Future<String?> Function();
typedef BrowserWebViewDelay = Future<void> Function(Duration duration);

class BrowserWebViewNavigationSnapshot {
  const BrowserWebViewNavigationSnapshot({
    required this.canGoBack,
    required this.canGoForward,
  });

  final bool canGoBack;
  final bool canGoForward;
}

class BrowserWebViewLoadSnapshot extends BrowserWebViewNavigationSnapshot {
  const BrowserWebViewLoadSnapshot({
    required this.title,
    required super.canGoBack,
    required super.canGoForward,
  });

  final String title;
}

class BrowserWebViewStateReader {
  const BrowserWebViewStateReader();

  Future<BrowserWebViewNavigationSnapshot?> readNavigationSnapshot({
    required BrowserWebViewAvailabilityCheck isAvailable,
    required BrowserWebViewBoolReader readCanGoBack,
    required BrowserWebViewBoolReader readCanGoForward,
  }) async {
    if (!isAvailable()) {
      return null;
    }

    final canGoBack = await readCanGoBack();
    final canGoForward = await readCanGoForward();
    if (!isAvailable()) {
      return null;
    }

    return BrowserWebViewNavigationSnapshot(
      canGoBack: canGoBack,
      canGoForward: canGoForward,
    );
  }

  Future<BrowserWebViewLoadSnapshot?> readLoadSnapshot({
    required BrowserWebViewAvailabilityCheck isAvailable,
    required BrowserWebViewTitleReader readTitle,
    required BrowserWebViewBoolReader readCanGoBack,
    required BrowserWebViewBoolReader readCanGoForward,
    Duration delay = const Duration(milliseconds: 200),
    BrowserWebViewDelay wait = Future<void>.delayed,
  }) async {
    await wait(delay);
    if (!isAvailable()) {
      return null;
    }

    final results = await Future.wait<Object?>([
      readTitle(),
      readCanGoBack(),
      readCanGoForward(),
    ]);
    if (!isAvailable()) {
      return null;
    }

    return BrowserWebViewLoadSnapshot(
      title: (results[0] as String?) ?? '',
      canGoBack: results[1] as bool,
      canGoForward: results[2] as bool,
    );
  }
}
