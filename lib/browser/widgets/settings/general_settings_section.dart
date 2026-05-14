import 'package:flutter/material.dart';

import 'settings_section_widgets.dart';

class GeneralSettingsSection extends StatelessWidget {
  const GeneralSettingsSection({
    super.key,
    required this.homepageController,
    required this.openNewWindowInTab,
    required this.onHomepageChanged,
    required this.onOpenNewWindowInTabChanged,
    required this.onClearBrowsingDataTap,
  });

  final TextEditingController homepageController;
  final bool openNewWindowInTab;
  final ValueChanged<String> onHomepageChanged;
  final ValueChanged<bool> onOpenNewWindowInTabChanged;
  final VoidCallback onClearBrowsingDataTap;

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
      ],
    );
  }
}
