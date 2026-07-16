part of 'downloads_page.dart';

extension _DownloadsPageActions on _DownloadsPageState {
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

  Future<void> _playVideo(BrowserDownloadRecord record) async {
    final savedPath = record.savedPath?.trim();
    if (savedPath == null || savedPath.isEmpty) {
      _showToast('视频文件路径不存在');
      return;
    }

    final settings = await _settingsService.loadSettings();
    if (!mounted) {
      return;
    }
    await _videoPlayerCoordinator.showFloatingVideoPlayer(
      context: context,
      url: Uri.file(savedPath).toString(),
      settings: settings,
      currentPageTitle: '视频播放',
    );
  }

  Future<void> _deleteRecord(BrowserDownloadRecord record) async {
    final choice = await showDownloadDeleteDialog(
      context,
      fileName: record.fileName,
    );

    if (choice == null) {
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
        deletePartialFile: choice == DownloadDeleteChoice.recordAndFile,
      );

      await _downloadStore.delete(id);

      await _reloadDownloads();
      if (mounted) {
        _showToast(
          choice == DownloadDeleteChoice.recordAndFile
              ? '已删除下载记录和文件'
              : '已删除下载记录',
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showToast('删除下载记录失败，请稍后重试');
    }
  }

  Future<void> _clearDownloadRecords() async {
    final records = await _downloadStore.list(limit: 1000000);
    if (!mounted) {
      return;
    }
    if (records.isEmpty) {
      _showToast('暂无下载记录');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空下载记录'),
        content: const Text('确定清空全部下载记录吗？\n已下载文件不会被删除，正在下载的任务将停止。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空记录'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      for (final record in records) {
        final id = record.id;
        if (id == null || record.status != 'downloading') {
          continue;
        }
        await _downloadService.cancelDownload(
          id,
          savedPath: record.savedPath?.trim(),
          deletePartialFile: false,
        );
      }
      await _downloadStore.clearAll();
      await _reloadDownloads();
      if (mounted) {
        _showToast('已清空下载记录');
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showToast('清空下载记录失败，请稍后重试');
    }
  }

  Future<void> _showUrlDownloadDialog() async {
    final request = await showManualDownloadDialog(context);
    if (request == null) {
      return;
    }

    final url = request.url;
    final fileName = request.fileName;

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
}
