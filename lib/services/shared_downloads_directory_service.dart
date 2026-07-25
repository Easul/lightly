import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../core/storage/shared_downloads_access.dart';
import 'storage_access_gateway.dart';

class SharedDownloadsDirectoryService implements SharedDownloadsAccess {
  SharedDownloadsDirectoryService({
    Future<bool> Function()? hasFileAccessPermission,
    Future<bool> Function()? requestFileAccessPermission,
    Future<String?> Function()? getSharedDownloadsPath,
    Future<Directory?> Function()? getExternalStorageDirectoryFn,
    Future<Directory> Function()? getApplicationDocumentsDirectoryFn,
    Future<Directory?> Function()? getDownloadsDirectoryFn,
    Future<Directory> Function()? getTemporaryDirectoryFn,
    bool Function()? isAndroid,
  }) : _hasFileAccessPermission =
           hasFileAccessPermission ?? _defaultHasFileAccessPermission,
       _requestFileAccessPermission =
           requestFileAccessPermission ?? _defaultRequestFileAccessPermission,
       _getSharedDownloadsPath =
           getSharedDownloadsPath ?? _defaultGetSharedDownloadsPath,
       _getExternalStorageDirectory =
           getExternalStorageDirectoryFn ?? getExternalStorageDirectory,
       _getApplicationDocumentsDirectory =
           getApplicationDocumentsDirectoryFn ??
           getApplicationDocumentsDirectory,
       _getDownloadsDirectory =
           getDownloadsDirectoryFn ?? getDownloadsDirectory,
       _getTemporaryDirectory =
           getTemporaryDirectoryFn ?? getTemporaryDirectory,
       _isAndroid = isAndroid ?? (() => Platform.isAndroid);

  final Future<bool> Function() _hasFileAccessPermission;
  final Future<bool> Function() _requestFileAccessPermission;
  final Future<String?> Function() _getSharedDownloadsPath;
  final Future<Directory?> Function() _getExternalStorageDirectory;
  final Future<Directory> Function() _getApplicationDocumentsDirectory;
  final Future<Directory?> Function() _getDownloadsDirectory;
  final Future<Directory> Function() _getTemporaryDirectory;
  final bool Function() _isAndroid;

  @override
  Future<bool> hasFileAccessPermission() => _hasFileAccessPermission();

  @override
  Future<bool> requestFileAccessPermission() => _requestFileAccessPermission();

  @override
  Future<String?> getSharedDownloadsPath() => _getSharedDownloadsPath();

  @override
  Future<Directory> resolveDirectory({
    bool preferSharedDownloads = true,
    bool requestSharedAccessIfNeeded = false,
    String androidFallbackFolderName = 'browser_downloads',
    String nonAndroidFallbackFolderName = 'downloads',
  }) async {
    if (_isAndroid()) {
      if (preferSharedDownloads) {
        final sharedDirectory = await _resolveAndroidSharedDownloadsDirectory(
          requestSharedAccessIfNeeded: requestSharedAccessIfNeeded,
        );
        if (sharedDirectory != null) {
          return sharedDirectory;
        }
      }

      final baseDirectory =
          await _getExternalStorageDirectory() ??
          await _getApplicationDocumentsDirectory();
      return _ensureDirectory(
        Directory(path.join(baseDirectory.path, androidFallbackFolderName)),
      );
    }

    if (preferSharedDownloads) {
      final downloadsDirectory = await _getDownloadsDirectory();
      if (downloadsDirectory != null) {
        return _ensureDirectory(downloadsDirectory);
      }
    }

    final temporaryDirectory = await _getTemporaryDirectory();
    return _ensureDirectory(
      Directory(
        path.join(temporaryDirectory.path, nonAndroidFallbackFolderName),
      ),
    );
  }

  Future<Directory?> _resolveAndroidSharedDownloadsDirectory({
    required bool requestSharedAccessIfNeeded,
  }) async {
    final alreadyGranted = await hasFileAccessPermission();
    if (!alreadyGranted) {
      if (!requestSharedAccessIfNeeded) {
        return null;
      }
      final granted = await requestFileAccessPermission();
      if (!granted) {
        return null;
      }
    }

    for (final candidatePath in await _androidSharedDownloadCandidates()) {
      final directory = Directory(candidatePath);
      if (await _isDirectoryWritable(directory)) {
        return _ensureDirectory(directory);
      }
    }

    return null;
  }

  Future<List<String>> _androidSharedDownloadCandidates() async {
    final candidates = <String>[];

    final sharedPath = (await getSharedDownloadsPath())?.trim();
    if (sharedPath != null && sharedPath.isNotEmpty) {
      candidates.add(sharedPath);
    }

    final derivedFromExternal = await _deriveSharedDownloadsPathFromExternal();
    if (derivedFromExternal != null && derivedFromExternal.isNotEmpty) {
      candidates.add(derivedFromExternal);
    }

    candidates.add('/storage/emulated/0/Download');

    final unique = <String>[];
    for (final candidate in candidates) {
      if (!unique.contains(candidate)) {
        unique.add(candidate);
      }
    }
    return unique;
  }

  Future<String?> _deriveSharedDownloadsPathFromExternal() async {
    final externalDirectory = await _getExternalStorageDirectory();
    final externalPath = externalDirectory?.path.trim();
    if (externalPath == null || externalPath.isEmpty) {
      return null;
    }

    const androidDataSegment = '/Android/data/';
    final androidDataIndex = externalPath.indexOf(androidDataSegment);
    if (androidDataIndex <= 0) {
      return null;
    }

    final storageRoot = externalPath.substring(0, androidDataIndex);
    if (storageRoot.isEmpty) {
      return null;
    }

    return path.join(storageRoot, 'Download');
  }

  Future<bool> _isDirectoryWritable(Directory directory) async {
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final testFile = File(
        path.join(
          directory.path,
          '.write_test_${DateTime.now().millisecondsSinceEpoch}',
        ),
      );
      await testFile.writeAsBytes(<int>[0], flush: true);
      await testFile.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Directory> _ensureDirectory(Directory directory) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static Future<bool> _defaultHasFileAccessPermission() async {
    try {
      return await StorageAccessGateway.instance.hasFileAccessPermission();
    } on MissingPluginException {
      return true;
    }
  }

  static Future<bool> _defaultRequestFileAccessPermission() async {
    try {
      return await StorageAccessGateway.instance.requestFileAccessPermission();
    } on MissingPluginException {
      return true;
    }
  }

  static Future<String?> _defaultGetSharedDownloadsPath() async {
    try {
      return await StorageAccessGateway.instance.getSharedDownloadsPath();
    } on MissingPluginException {
      return null;
    }
  }
}
