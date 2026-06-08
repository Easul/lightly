import 'package:flutter/material.dart';

import '../browser/models/browser_download_record.dart';

class DownloadsEmptyState extends StatelessWidget {
  const DownloadsEmptyState({super.key, required this.onRefresh});

  final RefreshCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(
            Icons.download_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          const Center(child: Text('暂无下载记录')),
        ],
      ),
    );
  }
}

class DownloadsList extends StatelessWidget {
  const DownloadsList({
    super.key,
    required this.downloads,
    required this.onRefresh,
    required this.onPause,
    required this.onResume,
    required this.onInstall,
    required this.onPlayVideo,
    required this.onDelete,
  });

  final List<BrowserDownloadRecord> downloads;
  final RefreshCallback onRefresh;
  final ValueChanged<BrowserDownloadRecord> onPause;
  final ValueChanged<BrowserDownloadRecord> onResume;
  final ValueChanged<BrowserDownloadRecord> onInstall;
  final ValueChanged<BrowserDownloadRecord> onPlayVideo;
  final ValueChanged<BrowserDownloadRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: downloads.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final record = downloads[index];
          return DownloadRecordCard(
            record: record,
            onPause: onPause,
            onResume: onResume,
            onInstall: onInstall,
            onPlayVideo: onPlayVideo,
            onDelete: onDelete,
          );
        },
      ),
    );
  }
}

class DownloadRecordCard extends StatelessWidget {
  const DownloadRecordCard({
    super.key,
    required this.record,
    required this.onPause,
    required this.onResume,
    required this.onInstall,
    required this.onPlayVideo,
    required this.onDelete,
  });

  final BrowserDownloadRecord record;
  final ValueChanged<BrowserDownloadRecord> onPause;
  final ValueChanged<BrowserDownloadRecord> onResume;
  final ValueChanged<BrowserDownloadRecord> onInstall;
  final ValueChanged<BrowserDownloadRecord> onPlayVideo;
  final ValueChanged<BrowserDownloadRecord> onDelete;

  bool get _canInstall =>
      record.status == 'completed' &&
      record.fileName.toLowerCase().endsWith('.apk');

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(child: Icon(_statusIcon(record.status))),
        title: Text(
          record.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _DownloadRecordDetails(record: record),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (record.status == 'downloading' && record.id != null)
              TextButton(
                onPressed: () => onPause(record),
                child: const Text('暂停'),
              ),
            if (record.status == 'paused')
              TextButton(
                onPressed: () => onResume(record),
                child: const Text('继续'),
              ),
            if (_canInstall)
              TextButton(
                onPressed: () => onInstall(record),
                child: const Text('安装'),
              ),
            if (isPlayableDownloadedVideo(record))
              IconButton.filledTonal(
                onPressed: () => onPlayVideo(record),
                tooltip: '播放视频',
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            TextButton(
              onPressed: () => onDelete(record),
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    );
  }
}

bool isPlayableDownloadedVideo(BrowserDownloadRecord record) {
  if (record.status != 'completed') {
    return false;
  }
  final savedPath = record.savedPath?.trim();
  if (savedPath == null || savedPath.isEmpty) {
    return false;
  }
  final name = record.fileName.toLowerCase();
  final path = savedPath.toLowerCase();
  return _videoExtensions.any(
    (extension) => name.endsWith(extension) || path.endsWith(extension),
  );
}

const List<String> _videoExtensions = [
  '.mp4',
  '.m4v',
  '.mkv',
  '.webm',
  '.mov',
  '.avi',
  '.flv',
  '.3gp',
  '.ts',
];

class _DownloadRecordDetails extends StatelessWidget {
  const _DownloadRecordDetails({required this.record});

  final BrowserDownloadRecord record;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('状态：${_statusLabel(record.status)}'),
        const SizedBox(height: 4),
        Text(
          record.savedPath?.isNotEmpty == true
              ? _displayPath(record.savedPath!)
              : record.url,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '大小：${_formatBytes(record.bytesReceived)}'
          '${record.totalBytes > 0 ? ' / ${_formatBytes(record.totalBytes)}' : ''}',
        ),
        if (record.status == 'downloading') ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: _progressValue(record),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.downloading_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(_progressLabel(record)),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Text('时间：${record.createdAt.toLocal()}'),
      ],
    );
  }
}

IconData _statusIcon(String status) {
  switch (status) {
    case 'completed':
      return Icons.check_circle_outline;
    case 'failed':
      return Icons.error_outline;
    case 'downloading':
      return Icons.downloading_outlined;
    case 'paused':
      return Icons.pause_circle_outline;
    default:
      return Icons.schedule_outlined;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'completed':
      return '已完成';
    case 'failed':
      return '失败';
    case 'downloading':
      return '下载中';
    case 'paused':
      return '已暂停';
    default:
      return '等待中';
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '${bytes}B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)}KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
}

double? _progressValue(BrowserDownloadRecord record) {
  if (record.totalBytes <= 0 || record.bytesReceived <= 0) {
    return null;
  }
  return (record.bytesReceived / record.totalBytes).clamp(0.0, 1.0);
}

String _progressLabel(BrowserDownloadRecord record) {
  final progress = _progressValue(record);
  if (progress == null) {
    return '正在下载 ${_formatBytes(record.bytesReceived)}';
  }
  return '已下载 ${(progress * 100).toStringAsFixed(0)}%';
}

String _displayPath(String path) {
  const prefix = '/storage/emulated/0/';
  if (path.startsWith(prefix)) {
    return path.substring(prefix.length);
  }
  return path;
}
