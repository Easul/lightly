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
import '../proxy_service.dart';
import 'browser_download_store.dart';

class DownloadConfirmationResult {
  const DownloadConfirmationResult({required this.fileName});

  final String fileName;
}

class _DownloadCancelledException implements Exception {
  const _DownloadCancelledException();
}

class _ActiveDownloadSession {
  _ActiveDownloadSession({required this.client});

  final HttpClient client;
  IOSink? sink;
  bool cancelled = false;
  final Completer<void> done = Completer<void>();

  Future<void> cancel() async {
    cancelled = true;
    client.close(force: true);
    try {
      await sink?.close();
    } catch (_) {}
  }

  void complete() {
    if (!done.isCompleted) {
      done.complete();
    }
  }
}

class BrowserDownloadService {
  BrowserDownloadService({
    DateTime Function()? now,
    SharedDownloadsAccess? sharedDownloadsAccess,
  }) : _now = now ?? DateTime.now,
       _sharedDownloadsAccess =
           sharedDownloadsAccess ?? SharedDownloadsDirectoryService();

  final DateTime Function() _now;
  final SharedDownloadsAccess _sharedDownloadsAccess;
  static const int _downloadProgressPersistStepBytes = 256 * 1024;
  final Map<int, _ActiveDownloadSession> _activeDownloads =
      <int, _ActiveDownloadSession>{};

  Future<void> cancelDownload(
    int id, {
    String? savedPath,
    bool deletePartialFile = false,
  }) async {
    final session = _activeDownloads[id];
    if (session != null) {
      await session.cancel();
      await session.done.future;
    }

    if (deletePartialFile && savedPath != null && savedPath.trim().isNotEmpty) {
      final file = File(savedPath.trim());
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  String resolveFileName(DownloadStartRequest request) {
    final suggestedFileName = request.suggestedFilename?.trim();
    if (suggestedFileName != null && suggestedFileName.isNotEmpty) {
      return sanitizeFileName(suggestedFileName);
    }

    final contentDispositionName = _extractFilenameFromContentDisposition(
      request.contentDisposition,
    );
    if (contentDispositionName != null && contentDispositionName.isNotEmpty) {
      return sanitizeFileName(contentDispositionName);
    }

    final pathSegment = request.url.pathSegments.isNotEmpty
        ? request.url.pathSegments.last
        : '';
    if (pathSegment.isNotEmpty) {
      return sanitizeFileName(Uri.decodeComponent(pathSegment));
    }

    return _defaultFileName();
  }

  String resolveFileNameFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final pathSegment = uri.pathSegments.last;
      if (pathSegment.isNotEmpty) {
        return sanitizeFileName(Uri.decodeComponent(pathSegment));
      }
    }

    return _defaultFileName();
  }

  String sanitizeFileName(String name) {
    final sanitized = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
      return _defaultFileName();
    }
    return sanitized;
  }

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
  }) async {
    final client = HttpClient();
    client.findProxy = (uri) =>
        proxyService.findProxyForDownload(settings, uri);
    final id = record.id;
    if (id == null) {
      throw ArgumentError.value(
        record.id,
        'record.id',
        'Record id is required.',
      );
    }
    final session = _ActiveDownloadSession(client: client);
    _activeDownloads[id] = session;
    var currentRecord = record.copyWith(
      status: 'downloading',
      savedPath: savedPath,
    );
    await downloadStore.update(currentRecord);

    try {
      final outputFile = File(savedPath);
      if (!await outputFile.parent.exists()) {
        await outputFile.parent.create(recursive: true);
      }

      var resumedFromBytes = 0;
      if (await outputFile.exists()) {
        resumedFromBytes = await outputFile.length();
      }

      final httpRequest = await client.getUrl(Uri.parse(url));
      if (resumedFromBytes > 0) {
        httpRequest.headers.set(
          HttpHeaders.rangeHeader,
          'bytes=$resumedFromBytes-',
        );
      }
      final response = await httpRequest.close();
      if (response.statusCode < HttpStatus.ok ||
          response.statusCode >= HttpStatus.multipleChoices) {
        throw HttpException(
          'Download failed with status ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }

      var writeMode = FileMode.write;
      var bytesReceived = 0;
      var totalBytes = currentRecord.totalBytes;

      if (resumedFromBytes > 0) {
        if (response.statusCode == HttpStatus.partialContent) {
          writeMode = FileMode.append;
          bytesReceived = resumedFromBytes;
          totalBytes = _resolveResumedTotalBytes(
            response: response,
            resumedFromBytes: resumedFromBytes,
            fallbackTotalBytes: currentRecord.totalBytes,
          );
        } else {
          await outputFile.writeAsBytes(const <int>[]);
          resumedFromBytes = 0;
          totalBytes = response.contentLength > 0
              ? response.contentLength
              : currentRecord.totalBytes;
        }
      } else {
        totalBytes = response.contentLength > 0
            ? response.contentLength
            : currentRecord.totalBytes;
      }

      final sink = outputFile.openWrite(mode: writeMode);
      session.sink = sink;
      var lastPersistedBytes = bytesReceived;
      await for (final chunk in response) {
        if (session.cancelled) {
          throw const _DownloadCancelledException();
        }
        bytesReceived += chunk.length;
        sink.add(chunk);
        if (lastPersistedBytes == 0 ||
            bytesReceived - lastPersistedBytes >=
                _downloadProgressPersistStepBytes) {
          currentRecord = currentRecord.copyWith(
            bytesReceived: bytesReceived,
            totalBytes: totalBytes,
          );
          await downloadStore.update(currentRecord);
          lastPersistedBytes = bytesReceived;
        }
      }
      if (session.cancelled) {
        throw const _DownloadCancelledException();
      }
      await sink.close();

      totalBytes = totalBytes > 0 ? totalBytes : bytesReceived;
      currentRecord = currentRecord.copyWith(
        status: 'completed',
        totalBytes: totalBytes,
        bytesReceived: bytesReceived,
        savedPath: savedPath,
      );
      await downloadStore.update(currentRecord);
      // 扫描新下载的文件，让系统文件管理器可以看到
      unawaited(MediaScannerService.scanFile(savedPath));
      onStatus('下载完成：${record.fileName}');
    } on _DownloadCancelledException {
      return;
    } catch (_) {
      currentRecord = currentRecord.copyWith(status: 'failed');
      await downloadStore.update(currentRecord);
      onStatus('下载失败：${record.fileName}');
    } finally {
      _activeDownloads.remove(id);
      session.complete();
      client.close(force: true);
    }
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
    return 'download_${_now().millisecondsSinceEpoch}.bin';
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

  String? _extractFilenameFromContentDisposition(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    final utf8Match = RegExp(
      r"filename\*=UTF-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(value);
    if (utf8Match != null) {
      return Uri.decodeComponent(utf8Match.group(1) ?? '');
    }

    final filenameMatch = RegExp(
      r'filename="?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(value);
    return filenameMatch?.group(1);
  }

  int _resolveResumedTotalBytes({
    required HttpClientResponse response,
    required int resumedFromBytes,
    required int fallbackTotalBytes,
  }) {
    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange != null) {
      final match = RegExp(r'bytes\s+\d+-\d+/(\d+)').firstMatch(contentRange);
      final total = int.tryParse(match?.group(1) ?? '');
      if (total != null && total > 0) {
        return total;
      }
    }

    if (response.contentLength > 0) {
      return resumedFromBytes + response.contentLength;
    }

    return fallbackTotalBytes;
  }
}
