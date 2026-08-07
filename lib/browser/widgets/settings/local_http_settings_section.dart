import 'package:flutter/material.dart';

import 'settings_section_widgets.dart';

class LocalHttpSettingsSection extends StatelessWidget {
  const LocalHttpSettingsSection({
    super.key,
    required this.enabled,
    required this.stateLabel,
    required this.stateColor,
    required this.portText,
    required this.baseUrlText,
    required this.lanUrls,
    required this.bindAllInterfaces,
    required this.rootPathController,
    required this.favoriteRootPaths,
    required this.portController,
    required this.uploadKeyController,
    required this.onToggle,
    required this.onUseSharedDownloadsDirectory,
    required this.onAddFavoriteRootPath,
    required this.onSelectFavoriteRootPath,
    required this.onRemoveFavoriteRootPath,
    required this.onBindAllInterfacesChanged,
  });

  final bool enabled;
  final String stateLabel;
  final Color stateColor;
  final String portText;
  final String? baseUrlText;
  final List<String> lanUrls;
  final bool bindAllInterfaces;
  final TextEditingController rootPathController;
  final List<String> favoriteRootPaths;
  final TextEditingController portController;
  final TextEditingController uploadKeyController;
  final ValueChanged<bool> onToggle;
  final VoidCallback onUseSharedDownloadsDirectory;
  final VoidCallback onAddFavoriteRootPath;
  final ValueChanged<String> onSelectFavoriteRootPath;
  final ValueChanged<String> onRemoveFavoriteRootPath;
  final ValueChanged<bool> onBindAllInterfacesChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LocalHttpStatusCard(
          enabled: enabled,
          stateLabel: stateLabel,
          stateColor: stateColor,
          portText: portText,
          baseUrlText: baseUrlText,
          lanUrls: lanUrls,
          onToggle: onToggle,
        ),
        const SizedBox(height: 16),
        SettingsCard(
          children: [
            _LocalHttpServerForm(
              enabled: enabled,
              bindAllInterfaces: bindAllInterfaces,
              rootPathController: rootPathController,
              favoriteRootPaths: favoriteRootPaths,
              portController: portController,
              uploadKeyController: uploadKeyController,
              onUseSharedDownloadsDirectory: onUseSharedDownloadsDirectory,
              onAddFavoriteRootPath: onAddFavoriteRootPath,
              onSelectFavoriteRootPath: onSelectFavoriteRootPath,
              onRemoveFavoriteRootPath: onRemoveFavoriteRootPath,
              onBindAllInterfacesChanged: onBindAllInterfacesChanged,
            ),
          ],
        ),
      ],
    );
  }
}

class _LocalHttpServerForm extends StatelessWidget {
  const _LocalHttpServerForm({
    required this.enabled,
    required this.bindAllInterfaces,
    required this.rootPathController,
    required this.favoriteRootPaths,
    required this.portController,
    required this.uploadKeyController,
    required this.onUseSharedDownloadsDirectory,
    required this.onAddFavoriteRootPath,
    required this.onSelectFavoriteRootPath,
    required this.onRemoveFavoriteRootPath,
    required this.onBindAllInterfacesChanged,
  });

  final bool enabled;
  final bool bindAllInterfaces;
  final TextEditingController rootPathController;
  final List<String> favoriteRootPaths;
  final TextEditingController portController;
  final TextEditingController uploadKeyController;
  final VoidCallback onUseSharedDownloadsDirectory;
  final VoidCallback onAddFavoriteRootPath;
  final ValueChanged<String> onSelectFavoriteRootPath;
  final ValueChanged<String> onRemoveFavoriteRootPath;
  final ValueChanged<bool> onBindAllInterfacesChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: rootPathController,
          enabled: enabled,
          decoration: const InputDecoration(
            labelText: '托管目录路径',
            hintText: '/storage/emulated/0/Download/site',
            prefixIcon: Icon(Icons.folder_outlined),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '常用托管目录',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: enabled ? onAddFavoriteRootPath : null,
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: const Text('收藏当前路径'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        if (favoriteRootPaths.isEmpty)
          Text(
            '还没有收藏目录。填写路径后点“收藏当前路径”，下次可直接切换。',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          for (final path in favoriteRootPaths)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              enabled: enabled,
              leading: const Icon(Icons.folder_outlined),
              title: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: enabled ? () => onSelectFavoriteRootPath(path) : null,
              trailing: IconButton(
                tooltip: '移除常用目录',
                icon: const Icon(Icons.close_rounded, size: 19),
                onPressed: enabled
                    ? () => onRemoveFavoriteRootPath(path)
                    : null,
              ),
            ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: portController,
                enabled: enabled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'HTTP 端口（留空随机）',
                  prefixIcon: Icon(Icons.http_outlined),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: enabled ? onUseSharedDownloadsDirectory : null,
              child: const Text('下载目录'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: bindAllInterfaces,
          title: const Text('监听局域网（0.0.0.0）'),
          subtitle: const Text('开启后，局域网内其他设备可通过手机 IP 访问该目录'),
          onChanged: enabled ? onBindAllInterfacesChanged : null,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: uploadKeyController,
          enabled: enabled,
          decoration: const InputDecoration(
            labelText: '上传密钥（可选）',
            hintText: '留空表示局域网内可直接上传',
            prefixIcon: Icon(Icons.key_outlined),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '提示：支持目录浏览和网页上传。关闭局域网监听时仅本机可访问；开启后可通过手机 IP 访问。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _LocalHttpStatusCard extends StatelessWidget {
  const _LocalHttpStatusCard({
    required this.enabled,
    required this.stateLabel,
    required this.stateColor,
    required this.portText,
    required this.baseUrlText,
    required this.lanUrls,
    required this.onToggle,
  });

  final bool enabled;
  final String stateLabel;
  final Color stateColor;
  final String portText;
  final String? baseUrlText;
  final List<String> lanUrls;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: enabled,
          title: const Text('启用本地 HTTP 文件服务'),
          subtitle: const Text('将手机上的目录通过 http://localhost:端口 托管给浏览器访问'),
          onChanged: onToggle,
        ),
        const Divider(),
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: stateColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '服务状态：$stateLabel',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 8),
        Text(portText, style: Theme.of(context).textTheme.bodySmall),
        if (baseUrlText != null)
          Text(baseUrlText!, style: Theme.of(context).textTheme.bodySmall),
        for (final lanUrl in lanUrls)
          Text('局域网访问：$lanUrl', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
