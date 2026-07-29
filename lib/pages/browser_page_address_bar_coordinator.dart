import 'browser_page_input_resolver.dart';

class BrowserAddressBarPlan {
  const BrowserAddressBarPlan._({
    required this.target,
    required this.wasFavoritesPage,
    required this.shouldLoadInCurrentWebView,
    required this.shouldRebuildAfterAddressLoad,
    required this.shouldResetKeepAliveAfterAddressLoad,
  });

  const BrowserAddressBarPlan.empty()
    : this._(
        target: null,
        wasFavoritesPage: false,
        shouldLoadInCurrentWebView: false,
        shouldRebuildAfterAddressLoad: false,
        shouldResetKeepAliveAfterAddressLoad: false,
      );

  final String? target;
  final bool wasFavoritesPage;
  final bool shouldLoadInCurrentWebView;
  final bool shouldRebuildAfterAddressLoad;
  final bool shouldResetKeepAliveAfterAddressLoad;

  bool get isEmpty => target == null;
}

class BrowserPageAddressBarCoordinator {
  const BrowserPageAddressBarCoordinator({
    BrowserPageInputResolver inputResolver = const BrowserPageInputResolver(),
  }) : _inputResolver = inputResolver;

  final BrowserPageInputResolver _inputResolver;

  BrowserAddressBarPlan buildLoadPlan({
    required String rawValue,
    required bool isProxyActive,
    required bool isFavoritesPage,
    required bool hasWebViewController,
  }) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return const BrowserAddressBarPlan.empty();
    }

    final target = _inputResolver.resolve(
      trimmed,
      isProxyActive: isProxyActive,
    );
    return BrowserAddressBarPlan._(
      target: target,
      wasFavoritesPage: isFavoritesPage,
      shouldLoadInCurrentWebView: !isFavoritesPage && hasWebViewController,
      shouldRebuildAfterAddressLoad: isFavoritesPage,
      shouldResetKeepAliveAfterAddressLoad:
          isFavoritesPage || !hasWebViewController,
    );
  }
}
