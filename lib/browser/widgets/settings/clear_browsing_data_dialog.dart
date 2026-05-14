import 'package:flutter/material.dart';

import '../../services/browser_settings_action_handler.dart';

Future<BrowserClearDataSelection?> showClearBrowsingDataDialog(
  BuildContext context,
) async {
  var clearHistory = true;
  var clearCookiesAndSiteData = false;
  var clearCache = false;
  var clearDownloadRecords = false;
  var clearFavorites = false;
  var clearClipboard = false;
  var clearCalculatorHistory = false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('清除浏览数据'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: clearHistory,
                title: const Text('浏览历史'),
                subtitle: const Text('包含地址栏建议与访问记录'),
                onChanged: (value) => setDialogState(() {
                  clearHistory = value ?? false;
                }),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: clearCookiesAndSiteData,
                title: const Text('Cookie 与站点数据'),
                subtitle: const Text('会退出大多数网站登录状态'),
                onChanged: (value) => setDialogState(() {
                  clearCookiesAndSiteData = value ?? false;
                }),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: clearCache,
                title: const Text('WebView 缓存'),
                subtitle: const Text('这是全局缓存清理，不限单个网站'),
                onChanged: (value) => setDialogState(() {
                  clearCache = value ?? false;
                }),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: clearDownloadRecords,
                title: const Text('下载记录'),
                subtitle: const Text('仅清除记录，不删除已下载文件'),
                onChanged: (value) => setDialogState(() {
                  clearDownloadRecords = value ?? false;
                }),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: clearFavorites,
                title: const Text('收藏夹'),
                onChanged: (value) => setDialogState(() {
                  clearFavorites = value ?? false;
                }),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: clearClipboard,
                title: const Text('剪贴板内容'),
                onChanged: (value) => setDialogState(() {
                  clearClipboard = value ?? false;
                }),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: clearCalculatorHistory,
                title: const Text('计算器历史'),
                onChanged: (value) => setDialogState(() {
                  clearCalculatorHistory = value ?? false;
                }),
              ),
            ],
          ),
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
    ),
  );

  if (confirmed != true) {
    return null;
  }

  return BrowserClearDataSelection(
    history: clearHistory,
    cookiesAndSiteData: clearCookiesAndSiteData,
    cache: clearCache,
    downloadRecords: clearDownloadRecords,
    favorites: clearFavorites,
    clipboard: clearClipboard,
    calculatorHistory: clearCalculatorHistory,
  );
}
