import 'package:flutter/material.dart';

import 'settings_section_widgets.dart';

class GeneralSettingsSection extends StatelessWidget {
  static const List<int> appCacheAutoClearIntervalOptions = <int>[
    12,
    24,
    72,
    168,
  ];

  const GeneralSettingsSection({
    super.key,
    required this.homepageController,
    required this.desktopUserAgentController,
    required this.openNewWindowInTab,
    required this.appCacheAutoClearEnabled,
    required this.appCacheAutoClearIntervalHours,
    required this.isClearingAppCache,
    required this.onHomepageChanged,
    required this.onDesktopUserAgentChanged,
    required this.onOpenNewWindowInTabChanged,
    required this.onClearBrowsingDataTap,
    required this.onClearAppCacheTap,
    required this.onAppCacheAutoClearChanged,
    required this.onAppCacheAutoClearIntervalChanged,
  });

  final TextEditingController homepageController;
  final TextEditingController desktopUserAgentController;
  final bool openNewWindowInTab;
  final bool appCacheAutoClearEnabled;
  final int appCacheAutoClearIntervalHours;
  final bool isClearingAppCache;
  final ValueChanged<String> onHomepageChanged;
  final ValueChanged<String> onDesktopUserAgentChanged;
  final ValueChanged<bool> onOpenNewWindowInTabChanged;
  final VoidCallback onClearBrowsingDataTap;
  final VoidCallback onClearAppCacheTap;
  final ValueChanged<bool> onAppCacheAutoClearChanged;
  final ValueChanged<int> onAppCacheAutoClearIntervalChanged;

  String _intervalLabel(int hours) {
    if (hours % 24 == 0) {
      final days = hours ~/ 24;
      return days == 1 ? '每 1 天' : '每 $days 天';
    }
    return '每 $hours 小时';
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: [
        TextField(
          controller: homepageController,
          decoration: const InputDecoration(
            labelText: '主页 URL',
            prefixIcon: Icon(Icons.home_outlined),
          ),
          onChanged: onHomepageChanged,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: desktopUserAgentController,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '电脑模式 UA',
            hintText: '留空使用默认桌面 Chrome UA',
            prefixIcon: Icon(Icons.desktop_windows_outlined),
          ),
          onChanged: onDesktopUserAgentChanged,
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: openNewWindowInTab,
          title: const Text('新窗口默认打开为新标签页'),
          subtitle: Text(openNewWindowInTab ? '关闭后改为弹窗打开' : '当前改为弹窗打开'),
          onChanged: onOpenNewWindowInTabChanged,
        ),
        const SizedBox(height: 8),
        SettingsTile(
          icon: Icons.delete_sweep_outlined,
          title: '清除浏览数据',
          subtitle: '按分类清理历史、Cookie、缓存、下载记录等',
          onTap: onClearBrowsingDataTap,
        ),
        const SizedBox(height: 12),
        SettingsTile(
          icon: Icons.cleaning_services_outlined,
          title: isClearingAppCache ? '正在清理应用缓存' : '清理应用缓存',
          subtitle: isClearingAppCache
              ? '正在清理 WebView、图片和临时缓存'
              : '清理 WebView、图片和临时缓存，不删除账号与设置',
          onTap: isClearingAppCache ? () {} : onClearAppCacheTap,
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: appCacheAutoClearEnabled,
          title: const Text('定时自动清理应用缓存'),
          subtitle: Text(
            appCacheAutoClearEnabled
                ? _intervalLabel(appCacheAutoClearIntervalHours)
                : '关闭后仅手动清理',
          ),
          onChanged: onAppCacheAutoClearChanged,
        ),
        if (appCacheAutoClearEnabled) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: appCacheAutoClearIntervalHours,
            decoration: const InputDecoration(
              labelText: '自动清理频率',
              prefixIcon: Icon(Icons.schedule_outlined),
            ),
            items: appCacheAutoClearIntervalOptions
                .map(
                  (hours) => DropdownMenuItem<int>(
                    value: hours,
                    child: Text(_intervalLabel(hours)),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              onAppCacheAutoClearIntervalChanged(value);
            },
          ),
        ],
      ],
    );
  }
}
