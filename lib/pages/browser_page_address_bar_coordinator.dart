import 'browser_page_input_resolver.dart';

class BrowserAddressBarPlan {
  const BrowserAddressBarPlan._({
    required this.target,
    required this.wasFavoritesPage,
    required this.shouldOpenNativeVideo,
    required this.shouldLoadInCurrentWebView,
    required this.shouldRebuildAfterAddressLoad,
    required this.shouldResetKeepAliveAfterAddressLoad,
  });

  const BrowserAddressBarPlan.empty()
    : this._(
        target: null,
        wasFavoritesPage: false,
        shouldOpenNativeVideo: false,
        shouldLoadInCurrentWebView: false,
        shouldRebuildAfterAddressLoad: false,
        shouldResetKeepAliveAfterAddressLoad: false,
      );

  final String? target;
  final bool wasFavoritesPage;
  final bool shouldOpenNativeVideo;
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
    required bool shouldOpenNativeVideo,
  }) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return const BrowserAddressBarPlan.empty();
    }

    final target = _inputResolver.resolve(
      trimmed,
      isProxyActive: isProxyActive,
    );
    if (shouldOpenNativeVideo) {
      return BrowserAddressBarPlan._(
        target: target,
        wasFavoritesPage: isFavoritesPage,
        shouldOpenNativeVideo: true,
        shouldLoadInCurrentWebView: false,
        shouldRebuildAfterAddressLoad: false,
        shouldResetKeepAliveAfterAddressLoad: false,
      );
    }

    return BrowserAddressBarPlan._(
      target: target,
      wasFavoritesPage: isFavoritesPage,
      shouldOpenNativeVideo: false,
      shouldLoadInCurrentWebView: !isFavoritesPage && hasWebViewController,
      shouldRebuildAfterAddressLoad: isFavoritesPage,
      shouldResetKeepAliveAfterAddressLoad:
          !isFavoritesPage && !hasWebViewController,
    );
  }
}
