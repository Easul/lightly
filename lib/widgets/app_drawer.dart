import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_theme.dart';
import 'shared/sidebar_item.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, this.onOpenSettings});

  final Future<void> Function()? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(32)),
      ),
      backgroundColor: colorScheme.surface,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            decoration: BoxDecoration(
              color: AppColors.brandHeader,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.explore_rounded,
                    size: 28,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '若轻',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text('轻量浏览器', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                SidebarItem(
                  icon: Icons.language_rounded,
                  label: '浏览器',
                  selected: currentRoute == '/' || currentRoute == null,
                  onTap: () {
                    if (currentRoute == '/' || currentRoute == null) {
                      Navigator.pop(context);
                    } else {
                      Navigator.popUntil(context, ModalRoute.withName('/'));
                    }
                  },
                ),
                SidebarItem(
                  icon: Icons.grid_view_rounded,
                  label: '2048',
                  selected: currentRoute == '/game-2048',
                  onTap: () {
                    if (currentRoute == '/game-2048') {
                      Navigator.pop(context);
                    } else {
                      Navigator.pushNamed(context, '/game-2048');
                    }
                  },
                ),
                SidebarItem(
                  icon: Icons.calculate_rounded,
                  label: '计算器',
                  selected: currentRoute == '/calculator',
                  onTap: () {
                    if (currentRoute == '/calculator') {
                      Navigator.pop(context);
                    } else {
                      Navigator.pushNamed(context, '/calculator');
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Divider(color: colorScheme.outlineVariant),
                ),
                SidebarItem(
                  icon: Icons.content_paste_rounded,
                  label: '剪贴板',
                  selected: currentRoute == '/clipboard',
                  onTap: () {
                    if (currentRoute == '/clipboard') {
                      Navigator.pop(context);
                    } else {
                      Navigator.pushNamed(context, '/clipboard');
                    }
                  },
                ),
                SidebarItem(
                  icon: Icons.settings_rounded,
                  label: '设置',
                  selected: currentRoute == '/settings',
                  onTap: () async {
                    if (currentRoute == '/settings') {
                      Navigator.pop(context);
                    } else {
                      Navigator.pop(context);
                      if (onOpenSettings != null) {
                        await onOpenSettings!.call();
                      } else if (context.mounted) {
                        await Navigator.pushNamed(context, '/settings');
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          SafeArea(top: false, child: const _VersionFooter()),
        ],
      ),
    );
  }
}

class _VersionFooter extends StatefulWidget {
  const _VersionFooter();

  @override
  State<_VersionFooter> createState() => _VersionFooterState();
}

class _VersionFooterState extends State<_VersionFooter> {
  String _version = '';
  String _buildNumber = '';

  String get _displayVersion {
    if (_version.isEmpty) {
      return '';
    }
    final normalizedVersion = _version.startsWith('v')
        ? _version.substring(1)
        : _version;
    return normalizedVersion.contains('+')
        ? normalizedVersion
        : '$normalizedVersion+$_buildNumber';
  }

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = packageInfo.version;
          _buildNumber = packageInfo.buildNumber;
        });
      }
    } catch (e) {
      // Ignore errors, version will remain empty
    }
  }

  void _copyVersion() {
    if (_version.isNotEmpty) {
      final versionText = '若轻 v$_displayVersion';
      Clipboard.setData(ClipboardData(text: versionText));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('版本信息已复制'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_version.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: GestureDetector(
        onTap: _copyVersion,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'v$_displayVersion',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
