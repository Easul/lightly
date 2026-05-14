import 'package:flutter/material.dart';

import '../browser/services/browser_suggestion_service.dart';
import '../browser/widgets/browser_address_bar.dart';
import '../browser/widgets/browser_bottom_bar.dart';

class BrowserPageStatusBanner extends StatelessWidget {
  const BrowserPageStatusBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.55),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class BrowserPageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BrowserPageAppBar({
    super.key,
    required this.addressController,
    required this.addressFocusNode,
    required this.isSecure,
    required this.suggestionService,
    required this.onSecurityPressed,
    required this.onClear,
    required this.currentUrl,
    required this.onSubmitted,
    required this.isLoading,
    required this.onRefresh,
  });

  final TextEditingController addressController;
  final FocusNode addressFocusNode;
  final bool isSecure;
  final BrowserSuggestionService suggestionService;
  final VoidCallback onSecurityPressed;
  final VoidCallback onClear;
  final String currentUrl;
  final Future<void> Function(String value) onSubmitted;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: true,
      toolbarHeight: 52,
      title: BrowserAddressBar(
        controller: addressController,
        focusNode: addressFocusNode,
        isSecure: isSecure,
        suggestionService: suggestionService,
        onSecurityPressed: onSecurityPressed,
        onChanged: (_) {},
        onClear: onClear,
        currentUrl: currentUrl,
        onEditingComplete: addressFocusNode.unfocus,
        onSubmitted: onSubmitted,
        isLoading: isLoading,
        onRefresh: onRefresh,
      ),
    );
  }
}

class BrowserPageBottomBar extends StatelessWidget {
  const BrowserPageBottomBar({
    super.key,
    required this.canGoBack,
    required this.canGoForward,
    required this.isLoading,
    required this.tabCount,
    required this.proxyEnabled,
    required this.onBack,
    required this.onForward,
    required this.onHome,
    required this.onOpenTabs,
    required this.onOpenMoreActions,
    required this.onFindInPage,
  });

  final bool canGoBack;
  final bool canGoForward;
  final bool isLoading;
  final int tabCount;
  final bool proxyEnabled;
  final Future<void> Function() onBack;
  final Future<void> Function() onForward;
  final VoidCallback onHome;
  final Future<void> Function() onOpenTabs;
  final Future<void> Function() onOpenMoreActions;
  final Future<void> Function() onFindInPage;

  @override
  Widget build(BuildContext context) {
    return BrowserBottomBar(
      canGoBack: canGoBack,
      canGoForward: canGoForward,
      isLoading: isLoading,
      tabCount: tabCount,
      proxyEnabled: proxyEnabled,
      onBack: onBack,
      onForward: onForward,
      onHome: onHome,
      onOpenTabs: onOpenTabs,
      onOpenMoreActions: onOpenMoreActions,
      onFindInPage: onFindInPage,
    );
  }
}

class BrowserPageBodySection extends StatelessWidget {
  const BrowserPageBodySection({
    super.key,
    required this.isFavoritesPage,
    required this.favoritesChild,
    required this.webViewChild,
    required this.statusMessage,
  });

  final bool isFavoritesPage;
  final Widget favoritesChild;
  final Widget webViewChild;
  final String statusMessage;

  @override
  Widget build(BuildContext context) {
    if (isFavoritesPage) {
      return favoritesChild;
    }

    return Column(
      children: [
        Expanded(child: webViewChild),
        if (statusMessage.isNotEmpty)
          BrowserPageStatusBanner(message: statusMessage),
      ],
    );
  }
}
