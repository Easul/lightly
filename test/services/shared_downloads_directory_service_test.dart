import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/services/shared_downloads_directory_service.dart';
import 'package:path/path.dart' as path;

void main() {
  group('SharedDownloadsDirectoryService', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp(
        'shared_downloads_directory_service_test_',
      );
    });

    tearDown(() async {
      if (await sandbox.exists()) {
        await sandbox.delete(recursive: true);
      }
    });

    test(
      'uses shared Download path when Android permission already granted',
      () async {
        final sharedDirectory = Directory(path.join(sandbox.path, 'Download'));
        final service = SharedDownloadsDirectoryService(
          hasFileAccessPermission: () async => true,
          requestFileAccessPermission: () async => false,
          getSharedDownloadsPath: () async => sharedDirectory.path,
          getExternalStorageDirectoryFn: () async =>
              Directory(path.join(sandbox.path, 'external')),
          getApplicationDocumentsDirectoryFn: () async =>
              Directory(path.join(sandbox.path, 'documents')),
          getDownloadsDirectoryFn: () async => null,
          getTemporaryDirectoryFn: () async =>
              Directory(path.join(sandbox.path, 'temp')),
          isAndroid: () => true,
        );

        final resolved = await service.resolveDirectory(
          preferSharedDownloads: true,
        );

        expect(resolved.path, sharedDirectory.path);
        expect(await resolved.exists(), isTrue);
      },
    );

    test(
      'falls back to app directory when Android shared access is denied',
      () async {
        final externalDirectory = Directory(
          path.join(sandbox.path, 'external'),
        );
        final service = SharedDownloadsDirectoryService(
          hasFileAccessPermission: () async => false,
          requestFileAccessPermission: () async => false,
          getSharedDownloadsPath: () async =>
              path.join(sandbox.path, 'Download'),
          getExternalStorageDirectoryFn: () async => externalDirectory,
          getApplicationDocumentsDirectoryFn: () async =>
              Directory(path.join(sandbox.path, 'documents')),
          getDownloadsDirectoryFn: () async => null,
          getTemporaryDirectoryFn: () async =>
              Directory(path.join(sandbox.path, 'temp')),
          isAndroid: () => true,
        );

        final resolved = await service.resolveDirectory(
          preferSharedDownloads: true,
          requestSharedAccessIfNeeded: true,
          androidFallbackFolderName: 'exports',
        );

        expect(resolved.path, path.join(externalDirectory.path, 'exports'));
        expect(await resolved.exists(), isTrue);
      },
    );

    test(
      'requests permission before using shared Download path on Android',
      () async {
        var requestCount = 0;
        final sharedDirectory = Directory(path.join(sandbox.path, 'Download'));
        final service = SharedDownloadsDirectoryService(
          hasFileAccessPermission: () async => false,
          requestFileAccessPermission: () async {
            requestCount += 1;
            return true;
          },
          getSharedDownloadsPath: () async => sharedDirectory.path,
          getExternalStorageDirectoryFn: () async =>
              Directory(path.join(sandbox.path, 'external')),
          getApplicationDocumentsDirectoryFn: () async =>
              Directory(path.join(sandbox.path, 'documents')),
          getDownloadsDirectoryFn: () async => null,
          getTemporaryDirectoryFn: () async =>
              Directory(path.join(sandbox.path, 'temp')),
          isAndroid: () => true,
        );

        final resolved = await service.resolveDirectory(
          preferSharedDownloads: true,
          requestSharedAccessIfNeeded: true,
        );

        expect(requestCount, 1);
        expect(resolved.path, sharedDirectory.path);
      },
    );

    test(
      'derives shared Download path from external storage root when native path is unavailable',
      () async {
        final storageRoot = Directory(
          path.join(sandbox.path, 'storage', 'emulated', '0'),
        );
        final externalDirectory = Directory(
          path.join(
            storageRoot.path,
            'Android',
            'data',
            'lightly.tool',
            'files',
          ),
        );
        final derivedDownloadDirectory = Directory(
          path.join(storageRoot.path, 'Download'),
        );
        final service = SharedDownloadsDirectoryService(
          hasFileAccessPermission: () async => true,
          requestFileAccessPermission: () async => false,
          getSharedDownloadsPath: () async => null,
          getExternalStorageDirectoryFn: () async => externalDirectory,
          getApplicationDocumentsDirectoryFn: () async =>
              Directory(path.join(sandbox.path, 'documents')),
          getDownloadsDirectoryFn: () async => null,
          getTemporaryDirectoryFn: () async =>
              Directory(path.join(sandbox.path, 'temp')),
          isAndroid: () => true,
        );

        final resolved = await service.resolveDirectory(
          preferSharedDownloads: true,
        );

        expect(resolved.path, derivedDownloadDirectory.path);
        expect(await resolved.exists(), isTrue);
      },
    );
  });
}
