import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class BrowserBottomBar extends StatefulWidget {
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

  @override
  State<BrowserBottomBar> createState() => _BrowserBottomBarState();
}

class _BrowserBottomBarState extends State<BrowserBottomBar> {
  // Cached layout values — only recalculated when screen size changes.
  Size _lastSize = Size.zero;
  double _lastPaddingBottom = 0;
  double _barHeight = 64.0;
  double _horizontalPadding = 12.0;
  double _buttonSize = 48.0;
  double _buttonRadius = 18.0;
  double _iconSize = 22.0;
  double _verticalPadding = 6.0;
  double _maxContentWidth = 420.0;

  void _updateLayoutIfNeeded(Size size, double paddingBottom) {
    if (size == _lastSize && paddingBottom == _lastPaddingBottom) {
      return;
    }
    _lastSize = size;
    _lastPaddingBottom = paddingBottom;

    final compact = size.height < 720 || size.shortestSide < 380;
    _horizontalPadding = compact ? 6.0 : 12.0;
    _buttonSize = compact ? 40.0 : 48.0;
    _buttonRadius = compact ? 14.0 : 18.0;
    _iconSize = compact ? 19.0 : 22.0;
    _verticalPadding = compact ? 8.0 : 6.0;
    _maxContentWidth = compact ? 360.0 : 420.0;
    _barHeight = _buttonSize + _verticalPadding * 2 + paddingBottom;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = colorScheme.surfaceContainerHighest;
    final size = MediaQuery.sizeOf(context);
    final mediaPadding = MediaQuery.paddingOf(context);

    _updateLayoutIfNeeded(size, mediaPadding.bottom);

    return Container(
      height: _barHeight,
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
            horizontal: _horizontalPadding,
            vertical: _verticalPadding,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _maxContentWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _DockButton(
                    tooltip: '后退',
                    icon: Icons.arrow_back_rounded,
                    onPressed: widget.canGoBack ? widget.onBack : null,
                    buttonSize: _buttonSize,
                    borderRadius: _buttonRadius,
                    iconSize: _iconSize,
                    color: widget.canGoBack
                        ? colorScheme.onSurface
                        : colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  _DockButton(
                    tooltip: '前进',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: widget.canGoForward ? widget.onForward : null,
                    buttonSize: _buttonSize,
                    borderRadius: _buttonRadius,
                    iconSize: _iconSize,
                    color: widget.canGoForward
                        ? colorScheme.onSurface
                        : colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  _DockButton(
                    tooltip: '主页',
                    icon: Icons.home_rounded,
                    onPressed: widget.onHome,
                    buttonSize: _buttonSize,
                    borderRadius: _buttonRadius,
                    iconSize: _iconSize,
                    color: colorScheme.onSurface,
                  ),
                  _DockButton(
                    tooltip: '标签页',
                    icon: Icons.filter_none_rounded,
                    onPressed: widget.onOpenTabs,
                    buttonSize: _buttonSize,
                    borderRadius: _buttonRadius,
                    iconSize: _iconSize,
                    color: colorScheme.onSurface,
                    badge: widget.tabCount > 0 ? '${widget.tabCount}' : null,
                  ),
                  _DockButton(
                    tooltip: '更多',
                    icon: Icons.more_vert_rounded,
                    onPressed: widget.onOpenMoreActions,
                    buttonSize: _buttonSize,
                    borderRadius: _buttonRadius,
                    iconSize: _iconSize,
                    color: colorScheme.onSurface,
                  ),
                ],
              ),
            ),
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
