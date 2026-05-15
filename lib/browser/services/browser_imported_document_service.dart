import 'package:flutter/services.dart';

import 'browser_favorite_service.dart';

class BrowserImportedDocumentService {
  BrowserImportedDocumentService({
    BrowserFavoriteService? favoriteService,
    Future<bool> Function(List<String> retainedUrls)? cleanupImportedFiles,
  }) : _favoriteService = favoriteService ?? BrowserFavoriteService(),
       _cleanupImportedFiles =
           cleanupImportedFiles ?? _defaultCleanupImportedFiles;

  static const MethodChannel _browserProxyChannel = MethodChannel(
    'browser_proxy',
  );

  final BrowserFavoriteService _favoriteService;
  final Future<bool> Function(List<String> retainedUrls) _cleanupImportedFiles;

  Future<void> cleanupUnfavoritedImportedFiles() async {
    final favorites = await _favoriteService.query();
    final retainedUrls = favorites
        .map((favorite) => favorite.url)
        .toList(growable: false);
    await _cleanupImportedFiles(retainedUrls);
  }

  static Future<bool> _defaultCleanupImportedFiles(
    List<String> retainedUrls,
  ) async {
    try {
      return await _browserProxyChannel.invokeMethod<bool>(
            'cleanupImportedPrivateFiles',
            {'retainedUrls': retainedUrls},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }
}
