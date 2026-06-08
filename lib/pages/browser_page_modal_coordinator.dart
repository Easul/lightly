import 'package:flutter/material.dart';

import '../browser/models/browser_tab_session.dart';
import '../browser/widgets/browser_favorites_menu_sheet.dart';
import 'browser_page_modal_actions.dart';
import 'browser_page_overlay_state_manager.dart';

typedef BrowserTabSwitcherPresenter =
    Future<void> Function({
      required BuildContext context,
      required List<BrowserTabSession> tabs,
      required String? activeTabId,
      required ValueChanged<String> onSelectTab,
      required ValueChanged<String> onCloseTab,
      required VoidCallback onCloseAll,
      required VoidCallback onNewTab,
    });

typedef BrowserMoreActionsPresenter =
    Future<void> Function({
      required BuildContext context,
      required bool proxyEnabled,
      required bool isFavorited,
      required VoidCallback? onToggleFavorite,
      required VoidCallback onToggleProxy,
      required VoidCallback onOpenDownloads,
      required VoidCallback onOpenDataManagement,
      required VoidCallback onCloseTab,
      required VoidCallback onOpenSettings,
      required VoidCallback onEnterFloatingWindowMode,
      required VoidCallback onExitApp,
      required VoidCallback? onOpenFavoritesMenu,
    });

typedef BrowserFavoritesMenuPresenter =
    Future<void> Function({
      required BuildContext context,
      required VoidCallback onAddFavorite,
      required VoidCallback onToggleReorderMode,
    });

class BrowserPageModalCoordinator {
  const BrowserPageModalCoordinator({
    this.showTabSwitcherModal = showBrowserTabSwitcherModal,
    this.showMoreActionsModal = showBrowserMoreActionsModal,
    this.showFavoritesMenuSheet = showBrowserFavoritesMenuSheet,
  });

  final BrowserTabSwitcherPresenter showTabSwitcherModal;
  final BrowserMoreActionsPresenter showMoreActionsModal;
  final BrowserFavoritesMenuPresenter showFavoritesMenuSheet;

  Future<void> showTabSwitcher({
    required BrowserPageOverlayStateManager overlayStateManager,
    required BuildContext context,
    required List<BrowserTabSession> tabs,
    required String? activeTabId,
    required ValueChanged<String> onSelectTab,
    required ValueChanged<String> onCloseTab,
    required VoidCallback onCloseAll,
    required VoidCallback onNewTab,
  }) async {
    overlayStateManager.handleOverlayOpened(trimKeepAlives: false);
    try {
      await showTabSwitcherModal(
        context: context,
        tabs: tabs,
        activeTabId: activeTabId,
        onSelectTab: onSelectTab,
        onCloseTab: onCloseTab,
        onCloseAll: onCloseAll,
        onNewTab: onNewTab,
      );
    } finally {
      overlayStateManager.handleOverlayClosed();
    }
  }

  Future<void> showMoreActions({
    required BrowserPageOverlayStateManager overlayStateManager,
    required BuildContext context,
    required bool proxyEnabled,
    required bool isFavorited,
    required VoidCallback? onToggleFavorite,
    required VoidCallback onToggleProxy,
    required VoidCallback onOpenDownloads,
    required VoidCallback onOpenDataManagement,
    required VoidCallback onCloseTab,
    required VoidCallback onOpenSettings,
    required VoidCallback onEnterFloatingWindowMode,
    required VoidCallback onExitApp,
    required VoidCallback? onOpenFavoritesMenu,
  }) async {
    overlayStateManager.handleOverlayOpened();
    try {
      await showMoreActionsModal(
        context: context,
        proxyEnabled: proxyEnabled,
        isFavorited: isFavorited,
        onToggleFavorite: onToggleFavorite,
        onToggleProxy: onToggleProxy,
        onOpenDownloads: onOpenDownloads,
        onOpenDataManagement: onOpenDataManagement,
        onCloseTab: onCloseTab,
        onOpenSettings: onOpenSettings,
        onEnterFloatingWindowMode: onEnterFloatingWindowMode,
        onExitApp: onExitApp,
        onOpenFavoritesMenu: onOpenFavoritesMenu,
      );
    } finally {
      overlayStateManager.handleOverlayClosed();
    }
  }

  Future<void> showFavoritesMenu({
    required BrowserPageOverlayStateManager overlayStateManager,
    required BuildContext context,
    required VoidCallback onAddFavorite,
    required VoidCallback onToggleReorderMode,
  }) async {
    overlayStateManager.handleOverlayOpened();
    try {
      await showFavoritesMenuSheet(
        context: context,
        onAddFavorite: onAddFavorite,
        onToggleReorderMode: onToggleReorderMode,
      );
    } finally {
      overlayStateManager.handleOverlayClosed();
    }
  }
}
