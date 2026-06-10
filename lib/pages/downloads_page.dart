import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

part 'downloads_page_actions.dart';

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

  Future<void> _copyDownloadLink(BrowserDownloadRecord record) async {
    await Clipboard.setData(ClipboardData(text: record.url));
    _showToast('链接已复制');
  }

  @override
  void dispose() {
    unawaited(_videoPlayerCoordinator.dispose());
    super.dispose();
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
                onCopyLink: (record) => unawaited(_copyDownloadLink(record)),
              );
            },
          );
        },
      ),
    );
  }
}
