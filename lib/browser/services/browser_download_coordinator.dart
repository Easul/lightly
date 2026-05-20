import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../browser_settings.dart';
import '../models/browser_download_record.dart';
import '../proxy_service.dart';
import '../../widgets/shared_download_access_dialog.dart';
import 'browser_download_service.dart';
import 'browser_download_store.dart';

class BrowserDownloadCoordinator {
  BrowserDownloadCoordinator({
    required BrowserDownloadService downloadService,
    required BrowserDownloadStore downloadStore,
    required ProxyService proxyService,
  }) : _downloadService = downloadService,
       _downloadStore = downloadStore,
       _proxyService = proxyService;

  final BrowserDownloadService _downloadService;
  final BrowserDownloadStore _downloadStore;
  final ProxyService _proxyService;

  static String? normalizeFloatingDownloadTitle(String rawTitle) {
    final trimmedTitle = rawTitle.trim();
    if (trimmedTitle.isEmpty || trimmedTitle == '视频播放') {
      return null;
    }

    final normalized = trimmedTitle
        .replaceFirst(RegExp(r'\s*-\s*YouTube\s*$', caseSensitive: false), '')
        .trim();
    return normalized.isEmpty ? null : normalized;
  }

  String resolveFloatingDownloadFileName(
    String downloadUrl, {
    String? pageTitle,
  }) {
    final title = pageTitle?.trim();
    if (title != null && title.isNotEmpty) {
      return _downloadService.sanitizeFileName('$title.mp4');
    }

    return _downloadService.resolveFileNameFromUrl(downloadUrl);
  }

  static String redactDownloadUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return url;
    }

    return uri.replace(userInfo: '', query: null, fragment: null).toString();
  }

  Future<void> startDownloadFromUrl({
    required BuildContext context,
    required String url,
    required BrowserSettings settings,
    required void Function(String) onStatus,
    OverlayEntry? dialogAnchorOverlay,
    String? displayUrl,
    String? suggestedFileName,
  }) async {
    final actualDisplayUrl = displayUrl ?? redactDownloadUrl(url);
    final fileName =
        suggestedFileName ?? _downloadService.resolveFileNameFromUrl(url);
    final pendingRecord = BrowserDownloadRecord(
      url: actualDisplayUrl,
      fileName: fileName,
      status: 'pending',
      savedPath: null,
      totalBytes: 0,
      bytesReceived: 0,
      createdAt: DateTime.now(),
    );

    final confirmation = await _showDownloadConfirmDialog(
      context: context,
      record: pendingRecord,
      onStatus: onStatus,
      copyUrl: actualDisplayUrl,
      dialogAnchorOverlay: dialogAnchorOverlay,
    );
    if (confirmation == null) {
      return;
    }

    final confirmedFileName = confirmation.fileName;
    if (!context.mounted) {
      return;
    }
    final useSystemDownloads = await _resolveSystemDownloadsPreference(
      context,
      onStatus: onStatus,
    );
    if (useSystemDownloads == null) {
      return;
    }
    final preparedRecord = await _downloadService.prepareDownload(
      url,
      confirmedFileName,
      useSystemDownloads: useSystemDownloads,
    );
    final savedPath = preparedRecord.savedPath;
    if (savedPath == null || savedPath.isEmpty) {
      onStatus('下载失败：无法确定保存路径');
      return;
    }

    final record = await _downloadStore.insert(
      preparedRecord.copyWith(url: actualDisplayUrl),
    );
    onStatus('开始下载：$confirmedFileName');
    unawaited(
      _downloadService.startDownload(
        url: url,
        record: record,
        savedPath: savedPath,
        proxyService: _proxyService,
        settings: settings,
        downloadStore: _downloadStore,
        onStatus: onStatus,
      ),
    );
  }

  Future<void> handleDownloadStart({
    required BuildContext context,
    required DownloadStartRequest request,
    required BrowserSettings settings,
    required void Function(String) onStatus,
  }) async {
    final downloadUrl = request.url.toString().trim();
    if (downloadUrl.isEmpty) {
      return;
    }

    final displayUrl = redactDownloadUrl(downloadUrl);
    final fileName = _downloadService.resolveFileName(request);
    final initialTotalBytes = request.contentLength < 0
        ? 0
        : request.contentLength;

    final pendingRecord = BrowserDownloadRecord(
      url: displayUrl,
      fileName: fileName,
      status: 'pending',
      savedPath: null,
      totalBytes: initialTotalBytes,
      bytesReceived: 0,
      createdAt: DateTime.now(),
    );

    final confirmation = await _showDownloadConfirmDialog(
      context: context,
      record: pendingRecord,
      onStatus: onStatus,
    );
    if (confirmation == null) {
      return;
    }

    final confirmedFileName = confirmation.fileName;
    if (!context.mounted) {
      return;
    }
    final useSystemDownloads = await _resolveSystemDownloadsPreference(
      context,
      onStatus: onStatus,
    );
    if (useSystemDownloads == null) {
      return;
    }
    final preparedRecord = await _downloadService.prepareDownload(
      downloadUrl,
      confirmedFileName,
      totalBytes: initialTotalBytes,
      useSystemDownloads: useSystemDownloads,
    );
    final persistedRecord = preparedRecord.copyWith(url: displayUrl);
    final savedPath = persistedRecord.savedPath;
    if (savedPath == null || savedPath.isEmpty) {
      onStatus('下载失败：无法确定保存路径');
      return;
    }

    final record = await _downloadStore.insert(persistedRecord);
    onStatus('开始下载：$confirmedFileName');
    unawaited(
      _downloadService.startDownload(
        url: downloadUrl,
        record: record,
        savedPath: savedPath,
        proxyService: _proxyService,
        settings: settings,
        downloadStore: _downloadStore,
        onStatus: onStatus,
      ),
    );
  }

  Future<bool?> _resolveSystemDownloadsPreference(
    BuildContext context, {
    required void Function(String) onStatus,
  }) async {
    if (!Platform.isAndroid) {
      return true;
    }

    final hasPermission = await _downloadService.hasStoragePermission();
    if (hasPermission) {
      return true;
    }
    if (!context.mounted) {
      return null;
    }

    final choice = await showSharedDownloadAccessDialog(
      context,
      actionLabel: '下载文件',
    );
    switch (choice) {
      case SharedDownloadAccessChoice.requestPermission:
        final granted = await _downloadService.requestStoragePermission();
        if (!granted) {
          onStatus('未获得 Download 授权，将保存到应用目录');
        }
        return granted;
      case SharedDownloadAccessChoice.useAppDirectory:
        onStatus('已改为保存到应用目录');
        return false;
      case SharedDownloadAccessChoice.cancel:
        return null;
    }
  }

  Future<DownloadConfirmationResult?> _showDownloadConfirmDialog({
    required BuildContext context,
    required BrowserDownloadRecord record,
    required void Function(String) onStatus,
    OverlayEntry? dialogAnchorOverlay,
    String? copyUrl,
  }) async {
    if (dialogAnchorOverlay == null) {
      return _downloadService.showConfirmDialog(context, record);
    }

    final overlay = Overlay.of(context);

    final completer = Completer<DownloadConfirmationResult?>();
    final fileNameController = TextEditingController(text: record.fileName);
    late final OverlayEntry entry;

    void closeWith(DownloadConfirmationResult? result) {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
      fileNameController.dispose();
      entry.remove();
    }

    entry = OverlayEntry(
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Material(
          color: Colors.black54,
          child: GestureDetector(
            onTap: () => closeWith(null),
            child: Center(
              child: GestureDetector(
                onTap: () {},
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '确认下载',
                                  style: theme.textTheme.titleLarge,
                                ),
                              ),
                              IconButton(
                                onPressed: () => closeWith(null),
                                icon: const Icon(Icons.close),
                                tooltip: '关闭',
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: fileNameController,
                            decoration: const InputDecoration(
                              labelText: '文件名',
                              hintText: '请输入保存文件名',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '保存位置：${record.savedPath?.isNotEmpty == true ? record.savedPath! : '未确定'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '来源：${record.url}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(
                                      text: (copyUrl ?? record.url).trim(),
                                    ),
                                  );
                                  onStatus('已复制下载链接');
                                },
                                icon: const Icon(Icons.copy_rounded),
                                tooltip: '复制链接',
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => closeWith(
                                  DownloadConfirmationResult(
                                    fileName: _downloadService.sanitizeFileName(
                                      fileNameController.text,
                                    ),
                                  ),
                                ),
                                child: const Text('下载'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry, above: dialogAnchorOverlay);
    return completer.future;
  }
}
