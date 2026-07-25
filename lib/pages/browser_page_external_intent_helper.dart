import 'package:flutter/services.dart';

import '../browser/services/external_intent_gateway.dart';

class BrowserPageExternalIntentHelper {
  BrowserPageExternalIntentHelper({ExternalIntentGateway? gateway})
    : _gateway = gateway ?? ExternalIntentGateway.instance;

  final ExternalIntentGateway _gateway;

  void setNewIntentUrlHandler(NewExternalIntentUrlHandler? handler) {
    _gateway.setNewIntentUrlHandler(handler);
  }

  Future<String?> getInitialIntentUrl() async {
    try {
      final url = await _gateway.getInitialIntentUrl();
      return await prepareExternalIntentUrl(url);
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> detachExternalIntent() async {
    try {
      await _gateway.detachExternalIntent();
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
      final mimeType = await _gateway.getContentMimeType(url);
      if (mimeType?.toLowerCase().startsWith('video/') == true) {
        return url;
      }
      final imported = await _gateway.importContentUriToPrivateFile(url);
      return imported?.isNotEmpty == true ? imported : url;
    } on MissingPluginException {
      return url;
    } catch (_) {
      return url;
    }
  }
}
