class BrowserPageStatusCoordinator {
  const BrowserPageStatusCoordinator();

  static const String _youtubeResolving = '正在解析 YouTube 视频';
  static const String _blockedPopup = '网页拦截了当前弹窗/跳转，请确认是否外部打开';
  static const String _externalAppContinuing = '检测到外部应用跳转，正在尝试继续';

  String cleared() => '';

  String youtubeResolving() => _youtubeResolving;

  String blockedPopup() => _blockedPopup;

  String externalAppContinuing() => _externalAppContinuing;

  String popupOpenedInNewTab() => '已在新标签页打开新窗口';

  bool shouldClearAfterAddressLoad({
    required bool wasFavoritesPage,
    required bool didChangeUrl,
    required String currentStatusMessage,
  }) {
    return wasFavoritesPage || didChangeUrl || currentStatusMessage.isNotEmpty;
  }

  bool shouldShowYoutubeResolving(String currentStatusMessage) {
    return currentStatusMessage != youtubeResolving();
  }

  String nextExternalStatus({
    required String? externalStatusMessage,
    required String currentStatusMessage,
  }) {
    return externalStatusMessage ?? currentStatusMessage;
  }
}
