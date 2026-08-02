import 'package:flutter/services.dart';

import '../../core/platform/platform_channel_names.dart';

class BrowserUserAgentMetadataGateway {
  const BrowserUserAgentMetadataGateway({
    MethodChannel channel = const MethodChannel(PlatformChannelNames.browser),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<bool> prepareWebView({
    required Object webViewId,
    String? desktopUserAgent,
  }) async {
    return await _channel.invokeMethod<bool>(
          _prepareWebViewMethod,
          <String, Object?>{
            'webViewId': webViewId,
            'desktopUserAgent': desktopUserAgent,
          },
        ) ??
        false;
  }

  static const String _prepareWebViewMethod = 'prepareBrowserWebView';
}
