import 'dart:io';

import 'package:path/path.dart' as path;

import '../../core/storage/shared_downloads_access.dart';
import 'browser_backup_models.dart';

class BrowserBackupFileWriter {
  BrowserBackupFileWriter({
    required SharedDownloadsAccess sharedDownloadsAccess,
  }) : _sharedDownloadsAccess = sharedDownloadsAccess;

  final SharedDownloadsAccess _sharedDownloadsAccess;

  Future<File> writeToDownloads(
    BrowserBackupData backup, {
    required bool requestSharedAccessIfNeeded,
  }) async {
    final downloadDirectory = await _sharedDownloadsAccess.resolveDirectory(
      preferSharedDownloads: true,
      requestSharedAccessIfNeeded: requestSharedAccessIfNeeded,
      androidFallbackFolderName: 'exports',
      nonAndroidFallbackFolderName: 'exports',
    );

    final now = DateTime.now();
    final timestamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
        '-${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
    final file = File(
      path.join(downloadDirectory.path, 'ruoqing-$timestamp.json'),
    );
    await file.writeAsString(backup.toJsonString());
    return file;
  }
}
