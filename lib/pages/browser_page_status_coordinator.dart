import 'browser_page_status_helper.dart';

class BrowserPageStatusCoordinator {
  const BrowserPageStatusCoordinator({
    BrowserPageStatusHelper helper = const BrowserPageStatusHelper(),
  }) : _helper = helper;

  final BrowserPageStatusHelper _helper;

  String cleared() => _helper.cleared();

  String youtubeResolving() => _helper.youtubeResolving();

  String blockedPopup() => _helper.blockedPopup();

  String externalAppContinuing() => _helper.externalAppContinuing();

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
