import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class SharedDownloadsDirectoryService {
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

  static const MethodChannel _browserProxyChannel = MethodChannel(
    'browser_proxy',
  );

  final Future<bool> Function() _hasFileAccessPermission;
  final Future<bool> Function() _requestFileAccessPermission;
  final Future<String?> Function() _getSharedDownloadsPath;
  final Future<Directory?> Function() _getExternalStorageDirectory;
  final Future<Directory> Function() _getApplicationDocumentsDirectory;
  final Future<Directory?> Function() _getDownloadsDirectory;
  final Future<Directory> Function() _getTemporaryDirectory;
  final bool Function() _isAndroid;

  Future<bool> hasFileAccessPermission() => _hasFileAccessPermission();

  Future<bool> requestFileAccessPermission() => _requestFileAccessPermission();

  Future<String?> getSharedDownloadsPath() => _getSharedDownloadsPath();

  Future<Directory> resolveDirectory({
    bool preferSharedDownloads = true,
    bool requestSharedAccessIfNeeded = false,
    String androidFallbackFolderName = 'browser_downloads',
    String nonAndroidFallbackFolderName = 'downloads',
  }) async {
    if (_isAndroid()) {
      if (preferSharedDownloads) {
        final canUseSharedDownloads = await _canUseSharedDownloads(
          requestSharedAccessIfNeeded: requestSharedAccessIfNeeded,
        );
        if (canUseSharedDownloads) {
          final sharedPath = (await getSharedDownloadsPath())?.trim();
          if (sharedPath != null && sharedPath.isNotEmpty) {
            return _ensureDirectory(Directory(sharedPath));
          }
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

  Future<bool> _canUseSharedDownloads({
    required bool requestSharedAccessIfNeeded,
  }) async {
    final alreadyGranted = await hasFileAccessPermission();
    if (!alreadyGranted) {
      if (!requestSharedAccessIfNeeded) {
        return false;
      }
      final granted = await requestFileAccessPermission();
      if (!granted) {
        return false;
      }
    }
    // Permission check passed, but verify the directory is actually writable
    // Some Android ROMs restrict access even with permissions granted
    final sharedPath = (await getSharedDownloadsPath())?.trim();
    if (sharedPath == null || sharedPath.isEmpty) {
      return false;
    }
    return _isDirectoryWritable(Directory(sharedPath));
  }

  /// Test if directory is actually writable by creating and deleting a temp file
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
      return await _browserProxyChannel.invokeMethod<bool>(
            'hasFileAccessPermission',
          ) ??
          false;
    } on MissingPluginException {
      return true;
    }
  }

  static Future<bool> _defaultRequestFileAccessPermission() async {
    try {
      return await _browserProxyChannel.invokeMethod<bool>(
            'requestFileAccessPermission',
          ) ??
          false;
    } on MissingPluginException {
      return true;
    }
  }

  static Future<String?> _defaultGetSharedDownloadsPath() async {
    try {
      return await _browserProxyChannel.invokeMethod<String>(
        'getSharedDownloadsPath',
      );
    } on MissingPluginException {
      return null;
    }
  }
}
