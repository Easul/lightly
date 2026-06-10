import 'dart:io';

import 'package:path/path.dart' as path;

import '../../services/shared_downloads_directory_service.dart';
import 'browser_backup_models.dart';

class BrowserBackupFileWriter {
  BrowserBackupFileWriter({
    required SharedDownloadsDirectoryService sharedDownloadsDirectoryService,
  }) : _sharedDownloadsDirectoryService = sharedDownloadsDirectoryService;

  final SharedDownloadsDirectoryService _sharedDownloadsDirectoryService;

  Future<File> writeToDownloads(
    BrowserBackupData backup, {
    required bool requestSharedAccessIfNeeded,
  }) async {
    final downloadDirectory = await _sharedDownloadsDirectoryService
        .resolveDirectory(
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
