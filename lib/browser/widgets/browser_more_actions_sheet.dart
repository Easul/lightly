import 'package:flutter/material.dart';

class BrowserMoreActionsSheet extends StatelessWidget {
  const BrowserMoreActionsSheet({
    super.key,
    required this.proxyEnabled,
    required this.isFavorited,
    required this.onToggleFavorite,
    required this.onToggleProxy,
    required this.onOpenDownloads,
    required this.onOpenDataManagement,
    required this.onCloseTab,
    required this.onOpenSettings,
    required this.onExitApp,
    this.onOpenFavoritesMenu,
    this.onFindInPage,
  });

  final bool proxyEnabled;
  final bool isFavorited;
  final VoidCallback? onToggleFavorite;
  final VoidCallback onToggleProxy;
  final VoidCallback onOpenDownloads;
  final VoidCallback onOpenDataManagement;
  final VoidCallback onCloseTab;
  final VoidCallback onOpenSettings;
  final VoidCallback onExitApp;
  final VoidCallback? onOpenFavoritesMenu;
  final VoidCallback? onFindInPage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              if (onToggleFavorite != null)
                _ActionItem(
                  icon: isFavorited
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  label: isFavorited ? '取消收藏' : '添加收藏',
                  iconColor: isFavorited ? colorScheme.primary : null,
                  onTap: () {
                    Navigator.pop(context);
                    onToggleFavorite!();
                  },
                ),
              _ActionItem(
                icon: Icons.download_rounded,
                label: '下载',
                onTap: () {
                  Navigator.pop(context);
                  onOpenDownloads();
                },
              ),
              _ActionItem(
                icon: Icons.import_export_rounded,
                label: '数据管理',
                onTap: () {
                  Navigator.pop(context);
                  onOpenDataManagement();
                },
              ),
              _ActionItem(
                icon: Icons.close_rounded,
                label: '关闭标签页',
                onTap: () {
                  Navigator.pop(context);
                  onCloseTab();
                },
              ),
              _ActionItem(
                icon: Icons.find_in_page_rounded,
                label: '页面内查找',
                onTap: () {
                  Navigator.pop(context);
                  onFindInPage?.call();
                },
              ),
              if (onOpenFavoritesMenu != null)
                _ActionItem(
                  icon: Icons.star_rounded,
                  label: '收藏',
                  onTap: () {
                    Navigator.pop(context);
                    onOpenFavoritesMenu!();
                  },
                ),
              Divider(
                indent: 16,
                endIndent: 16,
                color: colorScheme.outlineVariant,
              ),
              _ActionItem(
                icon: proxyEnabled
                    ? Icons.vpn_key_rounded
                    : Icons.vpn_key_off_rounded,
                label: proxyEnabled ? '关闭代理' : '开启代理',
                iconColor: proxyEnabled ? colorScheme.primary : null,
                onTap: () {
                  Navigator.pop(context);
                  onToggleProxy();
                },
              ),
              _ActionItem(
                icon: Icons.settings_rounded,
                label: '设置',
                onTap: () {
                  Navigator.pop(context);
                  onOpenSettings();
                },
              ),
              _ActionItem(
                icon: Icons.exit_to_app_rounded,
                label: '退出应用',
                onTap: () {
                  Navigator.pop(context);
                  onExitApp();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: iconColor ?? colorScheme.primary, size: 20),
      ),
      title: Text(label),
      trailing: Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: colorScheme.outline,
      ),
      onTap: onTap,
    );
  }
}
