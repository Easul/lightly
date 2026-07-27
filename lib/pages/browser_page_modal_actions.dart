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
}) async {
  VoidCallback? selectedAction;
  await _showBrowserModalSheet(
    context: context,
    builder: (sheetContext) => TabSwitcherSheet(
      tabs: tabs,
      activeTabId: activeTabId,
      onSelectTab: (tabId) {
        selectedAction = () => onSelectTab(tabId);
        Navigator.of(sheetContext).pop();
      },
      onCloseTab: (tabId) {
        selectedAction = () => onCloseTab(tabId);
        Navigator.of(sheetContext).pop();
      },
      onCloseAll: () {
        selectedAction = onCloseAll;
        Navigator.of(sheetContext).pop();
      },
      onNewTab: () {
        selectedAction = onNewTab;
        Navigator.of(sheetContext).pop();
      },
    ),
  );
  selectedAction?.call();
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
  required VoidCallback onOpenTools,
  required VoidCallback onCloseTab,
  required VoidCallback onOpenSettings,
  required VoidCallback onEnterFloatingWindowMode,
  required VoidCallback onExitApp,
  required VoidCallback? onOpenFavoritesMenu,
}) async {
  VoidCallback? selectedAction;
  VoidCallback deferAction(VoidCallback action) {
    return () {
      selectedAction = action;
    };
  }

  await _showBrowserModalSheet(
    context: context,
    builder: (sheetContext) => BrowserMoreActionsSheet(
      proxyEnabled: proxyEnabled,
      desktopModeEnabled: desktopModeEnabled,
      webDebugConsoleEnabled: webDebugConsoleEnabled,
      isFavorited: isFavorited,
      onToggleFavorite: onToggleFavorite == null
          ? null
          : deferAction(onToggleFavorite),
      onToggleProxy: deferAction(onToggleProxy),
      onToggleWebDebugConsole: deferAction(onToggleWebDebugConsole),
      onToggleDesktopMode: deferAction(onToggleDesktopMode),
      onOpenDownloads: deferAction(onOpenDownloads),
      onOpenTools: deferAction(onOpenTools),
      onCloseTab: deferAction(onCloseTab),
      onOpenSettings: deferAction(onOpenSettings),
      onEnterFloatingWindowMode: deferAction(onEnterFloatingWindowMode),
      onExitApp: deferAction(onExitApp),
      onOpenFavoritesMenu: onOpenFavoritesMenu == null
          ? null
          : deferAction(onOpenFavoritesMenu),
    ),
  );
  selectedAction?.call();
}

Future<void> _showBrowserModalSheet({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  final route = ModalBottomSheetRoute<void>(
    builder: builder,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    isScrollControlled: true,
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
  );
  await navigator.push<void>(route);
  await route.completed;
}
