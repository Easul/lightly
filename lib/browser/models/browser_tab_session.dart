import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class BrowserTabSession {
  const BrowserTabSession({
    required this.id,
    required this.url,
    this.keepAlive,
    this.popupWindowId,
    this.title = '',
    this.isLoading = false,
    this.canGoBack = false,
    this.canGoForward = false,
    this.scrollPosition = 0,
    this.isExternallyOpened = false,
  });

  final String id;
  final String url;
  final InAppWebViewKeepAlive? keepAlive;
  final int? popupWindowId;
  final String title;
  final bool isLoading;
  final bool canGoBack;
  final bool canGoForward;
  final double scrollPosition;
  final bool isExternallyOpened;

  String get displayTitle {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isNotEmpty) {
      return trimmedTitle;
    }
    return url;
  }

  BrowserTabSession copyWith({
    String? id,
    String? url,
    InAppWebViewKeepAlive? keepAlive,
    bool clearKeepAlive = false,
    int? popupWindowId,
    bool clearPopupWindowId = false,
    String? title,
    bool? isLoading,
    bool? canGoBack,
    bool? canGoForward,
    double? scrollPosition,
    bool? isExternallyOpened,
  }) {
    return BrowserTabSession(
      id: id ?? this.id,
      url: url ?? this.url,
      keepAlive: clearKeepAlive ? null : (keepAlive ?? this.keepAlive),
      popupWindowId: clearPopupWindowId
          ? null
          : (popupWindowId ?? this.popupWindowId),
      title: title ?? this.title,
      isLoading: isLoading ?? this.isLoading,
      canGoBack: canGoBack ?? this.canGoBack,
      canGoForward: canGoForward ?? this.canGoForward,
      scrollPosition: scrollPosition ?? this.scrollPosition,
      isExternallyOpened: isExternallyOpened ?? this.isExternallyOpened,
    );
  }
}
