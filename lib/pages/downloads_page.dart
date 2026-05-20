import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../browser/browser_settings_service.dart';
import '../browser/models/browser_download_record.dart';
import '../browser/proxy_service.dart';
import '../browser/services/browser_download_service.dart';
import '../browser/services/browser_download_store.dart';
import '../browser/services/browser_shared_services.dart';
import '../services/app_toast.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  final BrowserSharedServices _sharedServices = BrowserSharedServices.instance;
  BrowserDownloadService get _downloadService =>
      _sharedServices.downloadService;
  BrowserDownloadStore get _downloadStore => _sharedServices.downloadStore;
  BrowserSettingsService get _settingsService =>
      _sharedServices.settingsService;
  ProxyService get _proxyService => _sharedServices.proxyService;

  void _showToast(String message) {
    unawaited(AppToast.show(message));
  }

  Future<void> _reloadDownloads() async {
    await _downloadStore.list();
  }

  Future<void> _installApk(BrowserDownloadRecord record) async {
    final savedPath = record.savedPath?.trim();
    if (savedPath == null || savedPath.isEmpty) {
      if (!mounted) {
        return;
      }
      _showToast('安装文件路径不存在');
      return;
    }

    try {
      final result = await OpenFilex.open(savedPath);
      if (!mounted) {
        return;
      }
      if (result.type != ResultType.done) {
        _showToast('安装失败：${result.message}');
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showToast('安装失败，请稍后重试');
    }
  }

  Future<void> _deleteRecord(BrowserDownloadRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除“${record.fileName}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      final id = record.id;
      if (id == null) {
        throw StateError('Download record id is missing.');
      }

      final savedPath = record.savedPath?.trim();
      await _downloadService.cancelDownload(
        id,
        savedPath: savedPath,
        deletePartialFile: true,
      );

      await _downloadStore.delete(id);

      await _reloadDownloads();
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showToast('删除失败，请稍后重试');
    }
  }

  Future<void> _showUrlDownloadDialog() async {
    final urlController = TextEditingController();
    final fileNameController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('下载文件'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: '文件链接',
                hintText: 'https://example.com/file.zip',
              ),
              keyboardType: TextInputType.url,
              autofocus: true,
              onChanged: (value) {
                final uri = Uri.tryParse(value.trim());
                if (uri != null && uri.pathSegments.isNotEmpty) {
                  final segment = uri.pathSegments.last;
                  if (segment.isNotEmpty && fileNameController.text.isEmpty) {
                    fileNameController.text = segment;
                  }
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: fileNameController,
              decoration: const InputDecoration(
                labelText: '文件名',
                hintText: 'file.zip',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('下载'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      urlController.dispose();
      fileNameController.dispose();
      return;
    }

    final url = urlController.text.trim();
    final fileName = fileNameController.text.trim();
    urlController.dispose();
    fileNameController.dispose();

    if (url.isEmpty) {
      if (!mounted) return;
      _showToast('链接不能为空');
      return;
    }

    final normalizedUrl = url.contains('://') ? url : 'https://$url';
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      if (!mounted) return;
      _showToast('链接格式无效');
      return;
    }

    await _startManualDownload(
      normalizedUrl,
      fileName: fileName.isEmpty ? null : fileName,
    );
  }

  Future<void> _startManualDownload(String url, {String? fileName}) async {
    final resolvedFileName = fileName?.trim().isNotEmpty == true
        ? fileName!.trim()
        : _extractFileNameFromUrl(url);
    final pendingRecord = BrowserDownloadRecord(
      url: url,
      fileName: resolvedFileName,
      status: 'pending',
      savedPath: null,
      totalBytes: 0,
      bytesReceived: 0,
      createdAt: DateTime.now(),
    );

    final confirmation = await _downloadService.showConfirmDialog(
      context,
      pendingRecord,
    );

    if (confirmation == null) return;

    try {
      final hasPermission = await _downloadService.hasStoragePermission();
      final useSystemDir =
          hasPermission || await _downloadService.requestStoragePermission();

      final preparedRecord = await _downloadService.prepareDownload(
        url,
        confirmation.fileName,
        useSystemDownloads: useSystemDir,
      );
      final savedPath = preparedRecord.savedPath;
      if (savedPath == null || savedPath.isEmpty) {
        if (!mounted) return;
        _showToast('下载失败：无法确定保存路径');
        return;
      }

      final record = await _downloadStore.insert(preparedRecord);
      final settings = await _settingsService.loadSettings();

      if (!mounted) return;
      _showToast('开始下载：${confirmation.fileName}');

      await _downloadService.startDownload(
        url: url,
        record: record,
        savedPath: savedPath,
        proxyService: _proxyService,
        settings: settings,
        downloadStore: _downloadStore,
        onStatus: (message) {
          if (!mounted) return;
          _showToast(message);
        },
      );
      await _reloadDownloads();
    } catch (e) {
      if (!mounted) return;
      _showToast('下载失败：$e');
    }
  }

  String _extractFileNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final segment = uri.pathSegments.last;
      if (segment.isNotEmpty) {
        final sanitized = segment
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
            .trim();
        if (sanitized.isNotEmpty && sanitized != '.' && sanitized != '..') {
          return Uri.decodeComponent(sanitized);
        }
      }
    }
    return 'download_${DateTime.now().millisecondsSinceEpoch}.bin';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('下载记录')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showUrlDownloadDialog,
        child: const Icon(Icons.add_link),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: _downloadStore.changes,
        builder: (context, _, __) {
          return FutureBuilder<List<BrowserDownloadRecord>>(
            future: _downloadStore.list(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final downloads =
                  snapshot.data ?? const <BrowserDownloadRecord>[];
              if (downloads.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _reloadDownloads,
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

              return RefreshIndicator(
                onRefresh: _reloadDownloads,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: downloads.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final record = downloads[index];
                    final canInstall =
                        record.status == 'completed' &&
                        record.fileName.toLowerCase().endsWith('.apk');
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          child: Icon(_statusIcon(record.status)),
                        ),
                        title: Text(
                          record.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
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
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(_progressLabel(record)),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text('时间：${record.createdAt.toLocal()}'),
                            ],
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (record.status == 'downloading' &&
                                record.id != null)
                              TextButton(
                                onPressed: () => _pauseDownload(record),
                                child: const Text('暂停'),
                              ),
                            if (record.status == 'paused')
                              TextButton(
                                onPressed: () => _resumeDownload(record),
                                child: const Text('继续'),
                              ),
                            if (canInstall)
                              TextButton(
                                onPressed: () => _installApk(record),
                                child: const Text('安装'),
                              ),
                            TextButton(
                              onPressed: () => _deleteRecord(record),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
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

  Future<void> _pauseDownload(BrowserDownloadRecord record) async {
    final id = record.id;
    if (id == null) return;

    try {
      await _downloadService.cancelDownload(
        id,
        savedPath: record.savedPath,
        deletePartialFile: false,
      );
      await _downloadStore.update(record.copyWith(status: 'paused'));
      await _reloadDownloads();
      if (mounted) {
        _showToast('已暂停：${record.fileName}');
      }
    } catch (_) {
      if (mounted) {
        _showToast('暂停失败，请稍后重试');
      }
    }
  }

  Future<void> _resumeDownload(BrowserDownloadRecord record) async {
    try {
      final settings = await _settingsService.loadSettings();
      final resumedRecord = record.copyWith(status: 'downloading');
      await _downloadStore.update(resumedRecord);
      if (!mounted) return;
      _showToast('继续下载：${record.fileName}');
      await _downloadService.startDownload(
        url: record.url,
        record: resumedRecord,
        savedPath: record.savedPath ?? '',
        proxyService: _proxyService,
        settings: settings,
        downloadStore: _downloadStore,
        onStatus: (message) {
          if (!mounted) return;
          _showToast(message);
        },
      );
      await _reloadDownloads();
    } catch (e) {
      if (mounted) {
        _showToast('继续下载失败：$e');
      }
    }
  }

  /// Hides the common Android shared storage prefix for display.
  /// `/storage/emulated/0/Download/file.zip` → `Download/file.zip`
  String _displayPath(String path) {
    const prefix = '/storage/emulated/0/';
    if (path.startsWith(prefix)) {
      return path.substring(prefix.length);
    }
    return path;
  }
}
