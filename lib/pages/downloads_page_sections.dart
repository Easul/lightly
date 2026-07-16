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
    required this.onCopyLink,
  });

  final List<BrowserDownloadRecord> downloads;
  final RefreshCallback onRefresh;
  final ValueChanged<BrowserDownloadRecord> onPause;
  final ValueChanged<BrowserDownloadRecord> onResume;
  final ValueChanged<BrowserDownloadRecord> onInstall;
  final ValueChanged<BrowserDownloadRecord> onPlayVideo;
  final ValueChanged<BrowserDownloadRecord> onDelete;
  final ValueChanged<BrowserDownloadRecord> onCopyLink;

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
            onCopyLink: onCopyLink,
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
    required this.onCopyLink,
  });

  final BrowserDownloadRecord record;
  final ValueChanged<BrowserDownloadRecord> onPause;
  final ValueChanged<BrowserDownloadRecord> onResume;
  final ValueChanged<BrowserDownloadRecord> onInstall;
  final ValueChanged<BrowserDownloadRecord> onPlayVideo;
  final ValueChanged<BrowserDownloadRecord> onDelete;
  final ValueChanged<BrowserDownloadRecord> onCopyLink;

  bool get _canInstall =>
      record.status == 'completed' &&
      record.fileName.toLowerCase().endsWith('.apk');

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: () => _showActions(context),
        child: ListTile(
          dense: true,
          visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          leading: CircleAvatar(
            radius: 18,
            child: Icon(_statusIcon(record.status), size: 20),
          ),
          title: Text(
            record.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _DownloadRecordDetails(record: record),
          ),
          trailing: _DownloadRecordQuickActions(
            record: record,
            canInstall: _canInstall,
            onPause: onPause,
            onResume: onResume,
            onInstall: onInstall,
            onPlayVideo: onPlayVideo,
            onDelete: onDelete,
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制链接'),
              onTap: () {
                Navigator.of(context).pop();
                onCopyLink(record);
              },
            ),
            if (record.status == 'downloading' && record.id != null)
              ListTile(
                leading: const Icon(Icons.pause_rounded),
                title: const Text('暂停'),
                onTap: () {
                  Navigator.of(context).pop();
                  onPause(record);
                },
              ),
            if (record.status == 'paused')
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('继续'),
                onTap: () {
                  Navigator.of(context).pop();
                  onResume(record);
                },
              ),
            if (_canInstall)
              ListTile(
                leading: const Icon(Icons.android_rounded),
                title: const Text('安装'),
                onTap: () {
                  Navigator.of(context).pop();
                  onInstall(record);
                },
              ),
            if (isPlayableDownloadedVideo(record))
              ListTile(
                leading: const Icon(Icons.play_circle_outline_rounded),
                title: const Text('播放视频'),
                onTap: () {
                  Navigator.of(context).pop();
                  onPlayVideo(record);
                },
              ),
            ListTile(
              leading: Icon(
                Icons.delete,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '删除记录',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.of(context).pop();
                onDelete(record);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadRecordQuickActions extends StatelessWidget {
  const _DownloadRecordQuickActions({
    required this.record,
    required this.canInstall,
    required this.onPause,
    required this.onResume,
    required this.onInstall,
    required this.onPlayVideo,
    required this.onDelete,
  });

  final BrowserDownloadRecord record;
  final bool canInstall;
  final ValueChanged<BrowserDownloadRecord> onPause;
  final ValueChanged<BrowserDownloadRecord> onResume;
  final ValueChanged<BrowserDownloadRecord> onInstall;
  final ValueChanged<BrowserDownloadRecord> onPlayVideo;
  final ValueChanged<BrowserDownloadRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    if (record.status == 'downloading' && record.id != null) {
      return TextButton(
        onPressed: () => onPause(record),
        child: const Text('暂停'),
      );
    }
    if (record.status == 'paused') {
      return TextButton(
        onPressed: () => onResume(record),
        child: const Text('继续'),
      );
    }
    if (canInstall) {
      return TextButton(
        onPressed: () => onInstall(record),
        child: const Text('安装'),
      );
    }
    if (isPlayableDownloadedVideo(record)) {
      return IconButton.filledTonal(
        onPressed: () => onPlayVideo(record),
        tooltip: '播放视频',
        icon: const Icon(Icons.play_arrow_rounded),
      );
    }
    return IconButton(
      onPressed: () => onDelete(record),
      tooltip: '删除记录',
      icon: const Icon(Icons.delete_outline_rounded),
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
    final sizeText =
        '大小：${_formatBytes(record.bytesReceived)}'
        '${record.totalBytes > 0 ? ' / ${_formatBytes(record.totalBytes)}' : ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_statusLabel(record.status)} · $sizeText',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (record.status == 'downloading') ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: _progressValue(record),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _progressLabel(record),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ] else
          Text(
            record.savedPath?.isNotEmpty == true
                ? _displayPath(record.savedPath!)
                : record.url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
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
