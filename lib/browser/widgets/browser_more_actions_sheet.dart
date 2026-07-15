import 'package:flutter/material.dart';

class BrowserMoreActionsSheet extends StatelessWidget {
  const BrowserMoreActionsSheet({
    super.key,
    required this.proxyEnabled,
    required this.desktopModeEnabled,
    required this.webDebugConsoleEnabled,
    required this.isFavorited,
    required this.onToggleFavorite,
    required this.onToggleProxy,
    required this.onToggleWebDebugConsole,
    required this.onToggleDesktopMode,
    required this.onOpenDownloads,
    required this.onOpenDataManagement,
    required this.onCloseTab,
    required this.onOpenSettings,
    required this.onEnterFloatingWindowMode,
    required this.onExitApp,
    this.onOpenFavoritesMenu,
  });

  final bool proxyEnabled;
  final bool desktopModeEnabled;
  final bool webDebugConsoleEnabled;
  final bool isFavorited;
  final VoidCallback? onToggleFavorite;
  final VoidCallback onToggleProxy;
  final VoidCallback onToggleWebDebugConsole;
  final VoidCallback onToggleDesktopMode;
  final VoidCallback onOpenDownloads;
  final VoidCallback onOpenDataManagement;
  final VoidCallback onCloseTab;
  final VoidCallback onOpenSettings;
  final VoidCallback onEnterFloatingWindowMode;
  final VoidCallback onExitApp;
  final VoidCallback? onOpenFavoritesMenu;

  static const double _sheetMaxHeightFactor = 0.46;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final actions = <_ActionData>[
      if (onToggleFavorite != null)
        _ActionData(
          icon: isFavorited ? Icons.star_rounded : Icons.star_border_rounded,
          label: isFavorited ? '取消收藏' : '添加收藏',
          active: isFavorited,
          onTap: onToggleFavorite!,
        ),
      _ActionData(
        icon: Icons.download_outlined,
        label: '下载',
        onTap: onOpenDownloads,
      ),
      _ActionData(
        icon: Icons.import_export_rounded,
        label: '数据管理',
        onTap: onOpenDataManagement,
      ),
      _ActionData(icon: Icons.close_rounded, label: '关闭标签', onTap: onCloseTab),
      if (onOpenFavoritesMenu != null)
        _ActionData(
          icon: Icons.bookmarks_outlined,
          label: '收藏',
          onTap: onOpenFavoritesMenu!,
        ),
      _ActionData(
        icon: proxyEnabled ? Icons.vpn_key_rounded : Icons.vpn_key_off_outlined,
        label: proxyEnabled ? '关闭代理' : '开启代理',
        active: proxyEnabled,
        onTap: onToggleProxy,
      ),
      _ActionData(
        icon: webDebugConsoleEnabled
            ? Icons.bug_report_rounded
            : Icons.bug_report_outlined,
        label: '页面调试',
        active: webDebugConsoleEnabled,
        onTap: onToggleWebDebugConsole,
      ),
      _ActionData(
        icon: desktopModeEnabled
            ? Icons.smartphone_outlined
            : Icons.desktop_windows_outlined,
        label: desktopModeEnabled ? '手机模式' : '电脑模式',
        active: desktopModeEnabled,
        onTap: onToggleDesktopMode,
      ),
      _ActionData(
        icon: Icons.settings_outlined,
        label: '设置',
        onTap: onOpenSettings,
      ),
      _ActionData(
        icon: Icons.picture_in_picture_alt_outlined,
        label: '悬浮模式',
        onTap: onEnterFloatingWindowMode,
      ),
      _ActionData(
        icon: Icons.logout_rounded,
        label: '退出应用',
        danger: true,
        onTap: onExitApp,
      ),
    ];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * _sheetMaxHeightFactor,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columnCount = constraints.maxWidth >= 380 ? 5 : 4;
            final itemWidth = (constraints.maxWidth - 24) / columnCount;
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 34,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      children: actions
                          .map(
                            (action) => SizedBox(
                              width: itemWidth,
                              child: _ActionItem(
                                action: action,
                                onTap: () {
                                  Navigator.pop(context);
                                  action.onTap();
                                },
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ActionData {
  const _ActionData({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool danger;
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({required this.action, required this.onTap});

  final _ActionData action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final iconColor = action.danger
        ? colorScheme.error
        : action.active
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.82);
    final textColor = action.danger
        ? colorScheme.error.withValues(alpha: 0.92)
        : action.active
        ? colorScheme.primary.withValues(alpha: 0.92)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.9);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, color: iconColor, size: 23),
            const SizedBox(height: 7),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: textColor,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
