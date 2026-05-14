import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import '../browser_settings.dart';
import '../models/browser_download_record.dart';
import '../proxy_service.dart';
import '../../services/shared_downloads_directory_service.dart';
import 'browser_download_store.dart';

class DownloadConfirmationResult {
  const DownloadConfirmationResult({required this.fileName});

  final String fileName;
}

class BrowserDownloadService {
  BrowserDownloadService({
    DateTime Function()? now,
    SharedDownloadsDirectoryService? sharedDownloadsDirectoryService,
  }) : _now = now ?? DateTime.now,
       _sharedDownloadsDirectoryService =
           sharedDownloadsDirectoryService ?? SharedDownloadsDirectoryService();

  final DateTime Function() _now;
  final SharedDownloadsDirectoryService _sharedDownloadsDirectoryService;
  static const int _downloadProgressPersistStepBytes = 256 * 1024;

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
    return _sharedDownloadsDirectoryService.hasFileAccessPermission();
  }

  Future<bool> requestStoragePermission() async {
    return _sharedDownloadsDirectoryService.requestFileAccessPermission();
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
    var currentRecord = record.copyWith(
      status: 'downloading',
      savedPath: savedPath,
    );
    await downloadStore.update(currentRecord);

    try {
      final httpRequest = await client.getUrl(Uri.parse(url));
      final response = await httpRequest.close();
      if (response.statusCode < HttpStatus.ok ||
          response.statusCode >= HttpStatus.multipleChoices) {
        throw HttpException(
          'Download failed with status ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }

      final outputFile = File(savedPath);
      if (!await outputFile.parent.exists()) {
        await outputFile.parent.create(recursive: true);
      }

      final sink = outputFile.openWrite();
      var bytesReceived = 0;
      var lastPersistedBytes = 0;
      await for (final chunk in response) {
        bytesReceived += chunk.length;
        sink.add(chunk);
        if (lastPersistedBytes == 0 ||
            bytesReceived - lastPersistedBytes >=
                _downloadProgressPersistStepBytes) {
          currentRecord = currentRecord.copyWith(
            bytesReceived: bytesReceived,
            totalBytes: response.contentLength > 0
                ? response.contentLength
                : currentRecord.totalBytes,
          );
          await downloadStore.update(currentRecord);
          lastPersistedBytes = bytesReceived;
        }
      }
      await sink.close();

      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : (record.totalBytes > 0 ? record.totalBytes : bytesReceived);
      currentRecord = currentRecord.copyWith(
        status: 'completed',
        totalBytes: totalBytes,
        bytesReceived: bytesReceived,
        savedPath: savedPath,
      );
      await downloadStore.update(currentRecord);
      onStatus('下载完成：${record.fileName}');
    } catch (_) {
      currentRecord = currentRecord.copyWith(status: 'failed');
      await downloadStore.update(currentRecord);
      onStatus('下载失败：${record.fileName}');
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> getSystemDownloadPath() async {
    return _sharedDownloadsDirectoryService.getSharedDownloadsPath();
  }

  Future<Directory> _ensureDownloadsDirectory({
    bool preferSystem = true,
    bool requestStoragePermissionIfNeeded = false,
  }) async {
    return _sharedDownloadsDirectoryService.resolveDirectory(
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
      candidateName = '$baseName $suffix$extension';
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
}
