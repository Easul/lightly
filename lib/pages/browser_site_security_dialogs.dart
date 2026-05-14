import 'package:flutter/material.dart';

import 'browser_site_data_manager.dart';

Future<void> showBrowserSiteSecurityDialog({
  required BuildContext context,
  required BrowserSiteSecurityState state,
  required Future<void> Function() onClearSiteData,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(state.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(state.hostLabel),
          const SizedBox(height: 12),
          Text(state.description, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton.tonal(
          onPressed: state.canManageSiteData
              ? () async {
                  Navigator.of(context).pop();
                  await onClearSiteData();
                }
              : null,
          child: const Text('清除该网站数据'),
        ),
      ],
    ),
  );
}

Future<bool> showBrowserSiteDataClearConfirmation({
  required BuildContext context,
  required Uri currentUri,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('清除当前网站数据'),
      content: Text(
        '确定清除 ${currentUri.host} 的 Cookie 与站点数据吗？不包含 WebView 全局缓存。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('清除'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
