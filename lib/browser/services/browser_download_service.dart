import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import '../../core/storage/shared_downloads_access.dart';
import '../../services/media_scanner_service.dart';
import '../../services/shared_downloads_directory_service.dart';
import '../browser_settings.dart';
import '../models/browser_download_record.dart';
import '../../features/proxy/infrastructure/proxy_service.dart';
import 'browser_download_file_name_resolver.dart';
import 'browser_download_transfer.dart';
import 'browser_download_store.dart';

class DownloadConfirmationResult {
  const DownloadConfirmationResult({required this.fileName});

  final String fileName;
}

class BrowserDownloadService {
  BrowserDownloadService({
    DateTime Function()? now,
    SharedDownloadsAccess? sharedDownloadsAccess,
    BrowserDownloadFileNameResolver? fileNameResolver,
  }) : _now = now ?? DateTime.now,
       _sharedDownloadsAccess =
           sharedDownloadsAccess ?? SharedDownloadsDirectoryService(),
       _fileNameResolver =
           fileNameResolver ?? BrowserDownloadFileNameResolver(now: now);

  final DateTime Function() _now;
  final SharedDownloadsAccess _sharedDownloadsAccess;
  final BrowserDownloadFileNameResolver _fileNameResolver;
  final Map<int, BrowserDownloadTransfer> _activeDownloads =
      <int, BrowserDownloadTransfer>{};

  Future<void> cancelDownload(
    int id, {
    String? savedPath,
    bool deletePartialFile = false,
  }) async {
    final session = _activeDownloads[id];
    var partialFilePath = savedPath?.trim();
    if (session != null) {
      await session.cancel();
      await session.done;
      partialFilePath = session.outputFile?.path ?? partialFilePath;
    }

    if (deletePartialFile &&
        partialFilePath != null &&
        partialFilePath.isNotEmpty) {
      final file = File(partialFilePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  String resolveFileName(DownloadStartRequest request) {
    return _fileNameResolver.resolve(
      suggestedFileName: request.suggestedFilename,
      contentDisposition: request.contentDisposition,
      url: Uri.parse(request.url.toString()),
      mimeType: request.mimeType,
    );
  }

  String resolveFileNameFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      return _defaultFileName();
    }
    return _fileNameResolver.resolve(url: uri);
  }

  String sanitizeFileName(String name) => _fileNameResolver.sanitize(name);

  Future<DownloadConfirmationResult?> showConfirmDialog(
    BuildContext context,
    BrowserDownloadRecord record, {
    bool useRootNavigator = true,
  }) async {
    final fileNameController = TextEditingController(text: record.fileName);
    final result = await showDialog<DownloadConfirmationResult?>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认下载'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: fileNameController,
                decoration: const InputDecoration(
                  labelText: '文件名',
                  hintText: '请输入保存文件名',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '保存位置：${record.savedPath?.isNotEmpty == true ? record.savedPath! : '未确定'}',
              ),
              const SizedBox(height: 8),
              const Text('来源：'),
              const SizedBox(height: 4),
              Text(
                record.url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              DownloadConfirmationResult(
                fileName: sanitizeFileName(fileNameController.text),
              ),
            ),
            child: const Text('下载'),
          ),
        ],
      ),
    );
    fileNameController.dispose();
    return result;
  }

  Future<BrowserDownloadRecord> prepareDownload(
    String url,
    String filename, {
    int totalBytes = 0,
    bool useSystemDownloads = true,
  }) async {
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty) {
      throw ArgumentError.value(url, 'url', 'URL cannot be empty.');
    }

    final normalizedFileName = sanitizeFileName(filename);
    final downloadsDirectory = await _ensureDownloadsDirectory(
      preferSystem: useSystemDownloads,
    );
    final savedPath = await _resolveUniqueDownloadPath(
      downloadsDirectory,
      normalizedFileName,
    );

    return BrowserDownloadRecord(
      url: normalizedUrl,
      fileName: p.basename(savedPath),
      status: 'pending',
      savedPath: savedPath,
      totalBytes: totalBytes < 0 ? 0 : totalBytes,
      bytesReceived: 0,
      createdAt: _now(),
    );
  }

  Future<bool> hasStoragePermission() async {
    return _sharedDownloadsAccess.hasFileAccessPermission();
  }

  Future<bool> requestStoragePermission() async {
    return _sharedDownloadsAccess.requestFileAccessPermission();
  }

  Future<void> startDownload({
    required String url,
    required BrowserDownloadRecord record,
    required String savedPath,
    required ProxyService proxyService,
    required BrowserSettings settings,
    required BrowserDownloadStore downloadStore,
    required void Function(String) onStatus,
    Map<String, String> requestHeaders = const <String, String>{},
    bool allowResponseFileName = false,
  }) async {
    final id = record.id;
    if (id == null) {
      throw ArgumentError.value(
        record.id,
        'record.id',
        'Record id is required.',
      );
    }
    if (_activeDownloads.containsKey(id)) {
      onStatus('下载任务已在进行：${record.fileName}');
      return;
    }
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    client.findProxy = (uri) =>
        proxyService.findProxyForDownload(settings.proxyConfiguration, uri);
    final transfer = BrowserDownloadTransfer(client: client);
    _activeDownloads[id] = transfer;
    var effectiveSavedPath = savedPath;
    var currentRecord = record.copyWith(
      status: 'downloading',
      savedPath: effectiveSavedPath,
    );

    Future<void> markFailed() async {
      var actualBytes = currentRecord.bytesReceived;
      try {
        final outputFile = File(effectiveSavedPath);
        if (await outputFile.exists()) {
          actualBytes = await outputFile.length();
        }
      } catch (_) {}
      currentRecord = currentRecord.copyWith(
        status: 'failed',
        bytesReceived: actualBytes,
      );
      await downloadStore.update(currentRecord);
    }

    try {
      await downloadStore.update(currentRecord);
      final result = await transfer.run(
        url: Uri.parse(url),
        outputFile: File(effectiveSavedPath),
        requestHeaders: requestHeaders,
        initialTotalBytes: currentRecord.totalBytes,
        onProgress: (bytesReceived, totalBytes) async {
          currentRecord = currentRecord.copyWith(
            bytesReceived: bytesReceived,
            totalBytes: totalBytes,
          );
          await downloadStore.update(currentRecord);
        },
        onRetry: (retryNumber, maxRetries) {
          onStatus(
            '网络中断，正在重试（$retryNumber/$maxRetries）：${currentRecord.fileName}',
          );
        },
        validateResponse: (response) {
          if (isUnexpectedHtmlResponse(
            fileName: currentRecord.fileName,
            mimeType: response.headers.contentType?.mimeType,
          )) {
            throw const BrowserDownloadRejectedException(
              '下载失败：服务器返回的是网页，链接可能已失效或需要重新登录',
            );
          }
        },
        resolveOutputFile: allowResponseFileName
            ? (response, currentFile) async {
                final resolvedFileName = _fileNameResolver.resolveFromResponse(
                  currentFileName: currentRecord.fileName,
                  requestUrl: Uri.parse(url),
                  response: response,
                );
                if (resolvedFileName == null ||
                    resolvedFileName == currentRecord.fileName) {
                  return currentFile;
                }
                final resolvedPath = await _resolveUniqueDownloadPath(
                  currentFile.parent,
                  resolvedFileName,
                );
                return File(resolvedPath);
              }
            : null,
        onOutputFileChanged: (outputFile) async {
          effectiveSavedPath = outputFile.path;
          currentRecord = currentRecord.copyWith(
            fileName: p.basename(outputFile.path),
            savedPath: outputFile.path,
          );
          await downloadStore.update(currentRecord);
        },
      );

      effectiveSavedPath = result.outputFile.path;
      currentRecord = currentRecord.copyWith(
        status: 'completed',
        totalBytes: result.totalBytes,
        bytesReceived: result.bytesReceived,
        fileName: p.basename(effectiveSavedPath),
        savedPath: effectiveSavedPath,
      );
      await downloadStore.update(currentRecord);
      // 扫描新下载的文件，让系统文件管理器可以看到
      unawaited(MediaScannerService.scanFile(effectiveSavedPath));
      onStatus('下载完成：${currentRecord.fileName}');
    } on BrowserDownloadCancelledException {
      final outputFile = File(effectiveSavedPath);
      if (await outputFile.exists()) {
        currentRecord = currentRecord.copyWith(
          bytesReceived: await outputFile.length(),
        );
        await downloadStore.update(currentRecord);
      }
      return;
    } on BrowserDownloadRejectedException catch (error) {
      await markFailed();
      onStatus(error.message);
    } on BrowserDownloadHttpStatusException catch (error) {
      await markFailed();
      onStatus('下载失败：服务器返回 ${error.statusCode}（${currentRecord.fileName}）');
    } on BrowserDownloadProtocolException {
      await markFailed();
      onStatus('下载失败：服务器不支持可靠续传，请重试（${currentRecord.fileName}）');
    } catch (_) {
      await markFailed();
      onStatus('下载中断，已保留进度，可在下载记录中重试：${currentRecord.fileName}');
    } finally {
      _activeDownloads.remove(id);
      await transfer.finish();
    }
  }

  static bool isUnexpectedHtmlResponse({
    required String fileName,
    required String? mimeType,
  }) {
    final normalizedMimeType = mimeType?.trim().toLowerCase();
    if (normalizedMimeType != ContentType.html.mimeType &&
        normalizedMimeType != 'application/xhtml+xml') {
      return false;
    }

    final extension = p.extension(fileName).toLowerCase();
    return extension != '.html' &&
        extension != '.htm' &&
        extension != '.xhtml' &&
        extension != '.shtml';
  }

  Future<String?> getSystemDownloadPath() async {
    return _sharedDownloadsAccess.getSharedDownloadsPath();
  }

  Future<Directory> _ensureDownloadsDirectory({
    bool preferSystem = true,
    bool requestStoragePermissionIfNeeded = false,
  }) async {
    return _sharedDownloadsAccess.resolveDirectory(
      preferSharedDownloads: preferSystem,
      requestSharedAccessIfNeeded: requestStoragePermissionIfNeeded,
      androidFallbackFolderName: 'browser_downloads',
      nonAndroidFallbackFolderName: 'browser_downloads',
    );
  }

  String _defaultFileName() {
    return _fileNameResolver.resolve(url: Uri());
  }

  Future<String> _resolveUniqueDownloadPath(
    Directory directory,
    String fileName,
  ) async {
    final extension = p.extension(fileName);
    final baseName = extension.isEmpty
        ? fileName
        : fileName.substring(0, fileName.length - extension.length);

    var candidateName = fileName;
    var suffix = 1;
    while (await File(p.join(directory.path, candidateName)).exists()) {
      candidateName = '$baseName（$suffix）$extension';
      suffix += 1;
    }

    return p.join(directory.path, candidateName);
  }
}
