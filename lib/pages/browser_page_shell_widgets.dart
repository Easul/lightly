import 'package:flutter/foundation.dart';
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
    this.onChanged,
  });

  final TextEditingController addressController;
  final FocusNode addressFocusNode;
  final ValueListenable<bool> isSecure;
  final BrowserSuggestionService suggestionService;
  final VoidCallback onSecurityPressed;
  final VoidCallback onClear;
  final String currentUrl;
  final Future<void> Function(String value) onSubmitted;
  final ValueChanged<String>? onChanged;
  final ValueListenable<bool> isLoading;
  final Future<void> Function() onRefresh;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final mergedListenable = Listenable.merge([isSecure, isLoading]);
    return AppBar(
      automaticallyImplyLeading: true,
      toolbarHeight: 52,
      title: AnimatedBuilder(
        animation: mergedListenable,
        builder: (context, _) {
          return BrowserAddressBar(
            controller: addressController,
            focusNode: addressFocusNode,
            isSecure: isSecure.value,
            suggestionService: suggestionService,
            onSecurityPressed: onSecurityPressed,
            onChanged: onChanged ?? (_) {},
            onClear: onClear,
            currentUrl: currentUrl,
            onEditingComplete: addressFocusNode.unfocus,
            onSubmitted: onSubmitted,
            isLoading: isLoading.value,
            onRefresh: onRefresh,
          );
        },
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
  });

  final ValueListenable<bool> canGoBack;
  final ValueListenable<bool> canGoForward;
  final ValueListenable<bool> isLoading;
  final ValueListenable<int> tabCount;
  final bool proxyEnabled;
  final Future<void> Function() onBack;
  final Future<void> Function() onForward;
  final VoidCallback onHome;
  final Future<void> Function() onOpenTabs;
  final Future<void> Function() onOpenMoreActions;

  @override
  Widget build(BuildContext context) {
    final mergedListenable = Listenable.merge([
      isLoading,
      canGoBack,
      canGoForward,
      tabCount,
    ]);
    return AnimatedBuilder(
      animation: mergedListenable,
      builder: (context, _) {
        return BrowserBottomBar(
          canGoBack: canGoBack.value,
          canGoForward: canGoForward.value,
          isLoading: isLoading.value,
          tabCount: tabCount.value,
          proxyEnabled: proxyEnabled,
          onBack: onBack,
          onForward: onForward,
          onHome: onHome,
          onOpenTabs: onOpenTabs,
          onOpenMoreActions: onOpenMoreActions,
        );
      },
    );
  }
}

class BrowserPageBodySection extends StatelessWidget {
  const BrowserPageBodySection({
    super.key,
    required this.isFavoritesPage,
    required this.favoritesChild,
    required this.webViewChild,
    required this.freezeWebViewForOverlay,
    required this.statusMessage,
    required this.youtubePlayButtonVisible,
    required this.onYoutubePlayPressed,
  });

  final bool isFavoritesPage;
  final Widget favoritesChild;
  final Widget webViewChild;
  final ValueListenable<bool> freezeWebViewForOverlay;
  final ValueListenable<String> statusMessage;
  final bool youtubePlayButtonVisible;
  final VoidCallback onYoutubePlayPressed;

  @override
  Widget build(BuildContext context) {
    if (isFavoritesPage) {
      return favoritesChild;
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: Theme.of(context).colorScheme.surface),
              ValueListenableBuilder<bool>(
                valueListenable: freezeWebViewForOverlay,
                child: webViewChild,
                builder: (context, shouldFreezeWebView, child) {
                  return IgnorePointer(
                    key: const ValueKey('browserWebViewOverlayPointerBlocker'),
                    ignoring: shouldFreezeWebView,
                    child: child,
                  );
                },
              ),
              BrowserYoutubePlayBubble(
                visible: youtubePlayButtonVisible,
                onPressed: onYoutubePlayPressed,
              ),
            ],
          ),
        ),
        ValueListenableBuilder<String>(
          valueListenable: statusMessage,
          builder: (context, statusMessageValue, _) {
            if (statusMessageValue.isEmpty) {
              return const SizedBox.shrink();
            }
            return BrowserPageStatusBanner(message: statusMessageValue);
          },
        ),
      ],
    );
  }
}

class BrowserYoutubePlayBubble extends StatelessWidget {
  const BrowserYoutubePlayBubble({
    super.key,
    required this.visible,
    required this.onPressed,
  });

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      right: 18,
      bottom: 18,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 0.45),
          duration: const Duration(milliseconds: 420),
          curve: visible ? Curves.elasticOut : Curves.easeInCubic,
          child: AnimatedScale(
            scale: visible ? 1 : 0.78,
            duration: const Duration(milliseconds: 360),
            curve: visible ? Curves.elasticOut : Curves.easeInCubic,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: Material(
                color: Colors.transparent,
                elevation: visible ? 10 : 0,
                shadowColor: colorScheme.primary.withValues(alpha: 0.34),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: onPressed,
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [colorScheme.primary, colorScheme.tertiary],
                      ),
                      border: Border.all(
                        color: colorScheme.onPrimary.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 30,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
