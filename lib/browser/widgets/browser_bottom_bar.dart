import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class BrowserBottomBar extends StatelessWidget {
  const BrowserBottomBar({
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
    this.onFindInPage,
  });

  final bool canGoBack;
  final bool canGoForward;
  final bool isLoading;
  final int tabCount;
  final bool proxyEnabled;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback onHome;
  final VoidCallback onOpenTabs;
  final VoidCallback onOpenMoreActions;
  final VoidCallback? onFindInPage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = colorScheme.surfaceContainerHighest;
    final size = MediaQuery.sizeOf(context);
    final mediaPadding = MediaQuery.paddingOf(context);
    final compactLayout = size.height < 720 || size.shortestSide < 380;
    final compactVerticalPadding = 8.0;
    final barHeight = compactLayout
        ? 40.0 + compactVerticalPadding * 2 + mediaPadding.bottom
        : 98.0;
    final horizontalPadding = compactLayout ? 6.0 : 12.0;
    final buttonSize = compactLayout ? 40.0 : 48.0;
    final buttonRadius = compactLayout ? 14.0 : 18.0;
    final iconSize = compactLayout ? 19.0 : 22.0;

    return Container(
      height: barHeight,
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: AppTheme.softShadow(0.04),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: compactLayout ? compactVerticalPadding : 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _DockButton(
                tooltip: '后退',
                icon: Icons.arrow_back_rounded,
                onPressed: canGoBack ? onBack : null,
                buttonSize: buttonSize,
                borderRadius: buttonRadius,
                iconSize: iconSize,
                color: canGoBack
                    ? colorScheme.onSurface
                    : colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              _DockButton(
                tooltip: '前进',
                icon: Icons.arrow_forward_rounded,
                onPressed: canGoForward ? onForward : null,
                buttonSize: buttonSize,
                borderRadius: buttonRadius,
                iconSize: iconSize,
                color: canGoForward
                    ? colorScheme.onSurface
                    : colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              _DockButton(
                tooltip: '主页',
                icon: Icons.home_rounded,
                onPressed: onHome,
                buttonSize: buttonSize,
                borderRadius: buttonRadius,
                iconSize: iconSize,
                color: colorScheme.onSurface,
              ),
              _DockButton(
                tooltip: '标签页',
                icon: Icons.filter_none_rounded,
                onPressed: onOpenTabs,
                buttonSize: buttonSize,
                borderRadius: buttonRadius,
                iconSize: iconSize,
                color: colorScheme.onSurface,
                badge: tabCount > 0 ? '$tabCount' : null,
              ),
              _DockButton(
                tooltip: '更多',
                icon: Icons.more_vert_rounded,
                onPressed: onOpenMoreActions,
                buttonSize: buttonSize,
                borderRadius: buttonRadius,
                iconSize: iconSize,
                color: colorScheme.onSurface,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.color,
    required this.buttonSize,
    required this.borderRadius,
    this.iconSize = 22,
    this.badge,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final double buttonSize;
  final double borderRadius;
  final double iconSize;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          width: buttonSize,
          height: buttonSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onPressed == null
                ? Colors.transparent
                : Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: badge != null
              ? Badge(
                  label: Text(badge!, style: const TextStyle(fontSize: 10)),
                  child: Icon(icon, size: iconSize, color: color),
                )
              : Icon(icon, size: iconSize, color: color),
        ),
      ),
    );
  }
}
