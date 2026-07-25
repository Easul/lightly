import 'package:flutter/services.dart';

import 'browser_platform_gateway.dart';

typedef NewExternalIntentUrlHandler = Future<void> Function(String? url);

class ExternalIntentGateway {
  ExternalIntentGateway({
    MethodChannel channel = const MethodChannel(
      BrowserPlatformGateway.channelName,
    ),
  }) : _channel = channel;

  static final ExternalIntentGateway instance = ExternalIntentGateway();

  final MethodChannel _channel;

  void setNewIntentUrlHandler(NewExternalIntentUrlHandler? handler) {
    if (handler == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == _onNewIntentUrlMethod) {
        final arguments = call.arguments;
        final url = arguments is Map ? arguments['url'] as String? : null;
        await handler(url);
      }
    });
  }

  Future<String?> getInitialIntentUrl() {
    return _channel.invokeMethod<String>(_getInitialIntentUrlMethod);
  }

  Future<bool> detachExternalIntent() async {
    return await _channel.invokeMethod<bool>(_detachExternalIntentMethod) ??
        false;
  }

  Future<String?> getContentMimeType(String uri) {
    return _channel.invokeMethod<String>(
      _getContentMimeTypeMethod,
      <String, Object?>{'uri': uri},
    );
  }

  Future<String?> importContentUriToPrivateFile(String uri) {
    return _channel.invokeMethod<String>(
      _importContentUriToPrivateFileMethod,
      <String, Object?>{'uri': uri},
    );
  }

  Future<bool> cleanupImportedPrivateFiles(List<String> retainedUrls) async {
    return await _channel.invokeMethod<bool>(
          _cleanupImportedPrivateFilesMethod,
          <String, Object?>{'retainedUrls': retainedUrls},
        ) ??
        false;
  }

  static const String _onNewIntentUrlMethod = 'onNewIntentUrl';
  static const String _getInitialIntentUrlMethod = 'getInitialIntentUrl';
  static const String _detachExternalIntentMethod = 'detachExternalIntent';
  static const String _getContentMimeTypeMethod = 'getContentMimeType';
  static const String _importContentUriToPrivateFileMethod =
      'importContentUriToPrivateFile';
  static const String _cleanupImportedPrivateFilesMethod =
      'cleanupImportedPrivateFiles';
}
