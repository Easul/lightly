import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../browser/browser_settings_service.dart';
import '../browser/models/browser_download_record.dart';
import '../browser/proxy_service.dart';
import '../browser/services/browser_download_coordinator.dart';
import '../browser/services/browser_download_service.dart';
import '../browser/services/browser_download_store.dart';
import '../browser/services/browser_shared_services.dart';
import '../browser/services/browser_video_detection_tracker.dart';
import '../browser/services/browser_video_player_coordinator.dart';
import '../browser/services/browser_video_playback_preparation_service.dart';
import '../browser/services/external_api_video_source_resolver.dart';
import '../browser/services/video_proxy_server.dart';
import '../services/app_toast.dart';
import 'downloads_page_dialogs.dart';
import 'downloads_page_sections.dart';

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
  late final BrowserVideoDetectionTracker _videoDetectionTracker;
  late final VideoProxyServer _videoProxyServer;
  late final BrowserDownloadCoordinator _downloadCoordinator;
  late final BrowserVideoPlayerCoordinator _videoPlayerCoordinator;

  @override
  void initState() {
    super.initState();
    _videoDetectionTracker = BrowserVideoDetectionTracker();
    _videoProxyServer = VideoProxyServer();
    _downloadCoordinator = BrowserDownloadCoordinator(
      downloadService: _downloadService,
      downloadStore: _downloadStore,
      proxyService: _proxyService,
    );
    final playbackPreparationService = BrowserVideoPlaybackPreparationService(
      loadSettings: _settingsService.loadSettings,
      resolveVideoSource: (url, settings) {
        final resolver = ExternalApiVideoSourceResolver(
          apiBaseUrl: settings.normalizedNativeVideoParserApiBaseUrl,
          proxyService: _proxyService,
          settings: settings,
        );
        return resolver.resolve(url);
      },
      ensureProxyServer: (settings) {
        return _videoProxyServer.start(
          proxyService: _proxyService,
          settings: settings,
        );
      },
      buildProxyPlaybackUrl: _videoProxyServer.buildProxyUrl,
      redactDownloadUrl: BrowserDownloadCoordinator.redactDownloadUrl,
    );
    _videoPlayerCoordinator = BrowserVideoPlayerCoordinator(
      playbackPreparationService: playbackPreparationService,
      downloadCoordinator: _downloadCoordinator,
      videoDetectionTracker: _videoDetectionTracker,
      stopProxyServer: _videoProxyServer.stop,
      onShowSnackBar: _showToast,
      onDebugLog: (_) {},
    );
  }

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

  @override
  void dispose() {
    unawaited(_videoPlayerCoordinator.dispose());
    super.dispose();
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
        builder: (context, value, child) {
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
                return DownloadsEmptyState(onRefresh: _reloadDownloads);
              }

              return DownloadsList(
                downloads: downloads,
                onRefresh: _reloadDownloads,
                onPause: (record) => unawaited(_pauseDownload(record)),
                onResume: (record) => unawaited(_resumeDownload(record)),
                onInstall: (record) => unawaited(_installApk(record)),
                onPlayVideo: (record) => unawaited(_playVideo(record)),
                onDelete: (record) => unawaited(_deleteRecord(record)),
              );
            },
          );
        },
      ),
    );
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
