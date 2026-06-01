import 'package:flutter/services.dart';

class BrowserPageExternalIntentHelper {
  const BrowserPageExternalIntentHelper();

  static const MethodChannel browserProxyChannel = MethodChannel(
    'browser_proxy',
  );

  Future<String?> getInitialIntentUrl() async {
    try {
      final url = await browserProxyChannel.invokeMethod<String>(
        'getInitialIntentUrl',
      );
      return await prepareExternalIntentUrl(url);
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> detachExternalIntent() async {
    try {
      await browserProxyChannel.invokeMethod<bool>('detachExternalIntent');
    } on MissingPluginException {
      return;
    } catch (_) {
      return;
    }
  }

  Future<String?> prepareExternalIntentUrl(String? url) async {
    if (url == null || url.isEmpty) {
      return null;
    }

    final parsed = Uri.tryParse(url);
    if (parsed?.scheme.toLowerCase() != 'content') {
      return url;
    }

    try {
      final mimeType = await browserProxyChannel.invokeMethod<String>(
        'getContentMimeType',
        {'uri': url},
      );
      if (mimeType?.toLowerCase().startsWith('video/') == true) {
        return url;
      }
      final imported = await browserProxyChannel.invokeMethod<String>(
        'importContentUriToPrivateFile',
        {'uri': url},
      );
      return imported?.isNotEmpty == true ? imported : url;
    } on MissingPluginException {
      return url;
    } catch (_) {
      return url;
    }
  }
}
