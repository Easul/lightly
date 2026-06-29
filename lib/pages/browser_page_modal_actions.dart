import 'package:flutter/material.dart';

import '../browser/models/browser_tab_session.dart';
import '../browser/widgets/browser_more_actions_sheet.dart';
import '../browser/widgets/tab_switcher_sheet.dart';

Future<void> showBrowserTabSwitcherModal({
  required BuildContext context,
  required List<BrowserTabSession> tabs,
  required String? activeTabId,
  required ValueChanged<String> onSelectTab,
  required ValueChanged<String> onCloseTab,
  required VoidCallback onCloseAll,
  required VoidCallback onNewTab,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => TabSwitcherSheet(
      tabs: tabs,
      activeTabId: activeTabId,
      onSelectTab: (tabId) {
        Navigator.of(sheetContext).pop();
        onSelectTab(tabId);
      },
      onCloseTab: (tabId) {
        Navigator.of(sheetContext).pop();
        onCloseTab(tabId);
      },
      onCloseAll: () {
        Navigator.of(sheetContext).pop();
        onCloseAll();
      },
      onNewTab: () {
        Navigator.of(sheetContext).pop();
        onNewTab();
      },
    ),
  );
}

Future<void> showBrowserMoreActionsModal({
  required BuildContext context,
  required bool proxyEnabled,
  required bool desktopModeEnabled,
  required bool webDebugConsoleEnabled,
  required bool isFavorited,
  required VoidCallback? onToggleFavorite,
  required VoidCallback onToggleProxy,
  required VoidCallback onToggleWebDebugConsole,
  required VoidCallback onToggleDesktopMode,
  required VoidCallback onOpenDownloads,
  required VoidCallback onOpenDataManagement,
  required VoidCallback onCloseTab,
  required VoidCallback onOpenSettings,
  required VoidCallback onEnterFloatingWindowMode,
  required VoidCallback onExitApp,
  required VoidCallback? onOpenFavoritesMenu,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => BrowserMoreActionsSheet(
      proxyEnabled: proxyEnabled,
      desktopModeEnabled: desktopModeEnabled,
      webDebugConsoleEnabled: webDebugConsoleEnabled,
      isFavorited: isFavorited,
      onToggleFavorite: onToggleFavorite,
      onToggleProxy: onToggleProxy,
      onToggleWebDebugConsole: onToggleWebDebugConsole,
      onToggleDesktopMode: onToggleDesktopMode,
      onOpenDownloads: onOpenDownloads,
      onOpenDataManagement: onOpenDataManagement,
      onCloseTab: onCloseTab,
      onOpenSettings: onOpenSettings,
      onEnterFloatingWindowMode: onEnterFloatingWindowMode,
      onExitApp: onExitApp,
      onOpenFavoritesMenu: onOpenFavoritesMenu,
    ),
  );
}
