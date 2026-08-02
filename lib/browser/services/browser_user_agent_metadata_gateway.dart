import 'package:flutter/services.dart';

import '../../core/platform/platform_channel_names.dart';

class BrowserUserAgentMetadataGateway {
  const BrowserUserAgentMetadataGateway({
    MethodChannel channel = const MethodChannel(PlatformChannelNames.browser),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<bool> applyDesktopMetadata({
    required Object webViewId,
    required String userAgent,
  }) async {
    return await _channel.invokeMethod<bool>(
          _applyDesktopMetadataMethod,
          <String, Object>{'webViewId': webViewId, 'userAgent': userAgent},
        ) ??
        false;
  }

  static const String _applyDesktopMetadataMethod =
      'applyDesktopUserAgentMetadata';
}
