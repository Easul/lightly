import 'package:flutter/material.dart';

class DataExportSection extends StatelessWidget {
  const DataExportSection({
    super.key,
    required this.busy,
    required this.onExportToDownloads,
    required this.onExportToClipboard,
  });

  final bool busy;
  final VoidCallback onExportToDownloads;
  final VoidCallback onExportToClipboard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('导出', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : onExportToDownloads,
              icon: const Icon(Icons.download),
              label: const Text('导出到 Download/ruoqing-年月日.json'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : onExportToClipboard,
              icon: const Icon(Icons.copy),
              label: const Text('复制到剪贴板'),
            ),
          ],
        ),
      ],
    );
  }
}

class DataLogSection extends StatelessWidget {
  const DataLogSection({
    super.key,
    required this.busy,
    required this.logRecordingEnabled,
    required this.logPath,
    required this.onSetLogRecordingEnabled,
    required this.onExportLogsToDownloads,
    required this.onCopyLogsToClipboard,
  });

  final bool busy;
  final bool logRecordingEnabled;
  final String? logPath;
  final ValueChanged<bool> onSetLogRecordingEnabled;
  final VoidCallback onExportLogsToDownloads;
  final VoidCallback onCopyLogsToClipboard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('日志', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: logRecordingEnabled,
          title: const Text('启用运行日志记录'),
          subtitle: Text(
            logRecordingEnabled
                ? '已记录运行错误与关键事件，复现下载失败后可导出日志给我分析'
                : '关闭时不再追加新日志；开启后再复现问题可帮助排查下载失败',
          ),
          onChanged: busy ? null : onSetLogRecordingEnabled,
        ),
        if (logPath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '日志文件：$logPath',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : onExportLogsToDownloads,
              icon: const Icon(Icons.bug_report),
              label: const Text('导出运行日志到 Download'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : onCopyLogsToClipboard,
              icon: const Icon(Icons.copy),
              label: const Text('复制运行日志到剪贴板'),
            ),
          ],
        ),
      ],
    );
  }
}

class DataImportSection extends StatelessWidget {
  const DataImportSection({
    super.key,
    required this.busy,
    required this.onImportFromFile,
  });

  final bool busy;
  final VoidCallback onImportFromFile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('导入', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('通过选择备份文件恢复数据。导入设置后会在返回浏览器时自动重载相关运行配置。'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : onImportFromFile,
          icon: const Icon(Icons.upload_file),
          label: const Text('选择备份文件并导入'),
        ),
      ],
    );
  }
}
