import 'dart:io';

/// Cross-feature access to the user-visible Downloads directory.
///
/// Implementations own Android permission checks and app-writable fallbacks so
/// download, backup, and log features do not duplicate platform path policy.
abstract class SharedDownloadsAccess {
  Future<bool> hasFileAccessPermission();

  Future<bool> requestFileAccessPermission();

  Future<String?> getSharedDownloadsPath();

  Future<Directory> resolveDirectory({
    bool preferSharedDownloads = true,
    bool requestSharedAccessIfNeeded = false,
    String androidFallbackFolderName = 'browser_downloads',
    String nonAndroidFallbackFolderName = 'downloads',
  });
}
