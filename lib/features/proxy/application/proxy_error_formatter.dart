import 'dart:io';

import 'package:flutter/services.dart';

class ProxyErrorFormatter {
  const ProxyErrorFormatter();

  String describe(Object error) {
    if (error is PlatformException) {
      switch (error.code) {
        case 'UNSUPPORTED':
          return 'WebView proxy override is not supported on this device.';
        case 'INVALID_ARGUMENTS':
          return 'Invalid proxy configuration. Please check host and port.';
        default:
          return error.message ?? 'An unexpected proxy error occurred.';
      }
    }

    if (error is SocketException) {
      return 'Network error: ${error.message}. Please check your connection and server address.';
    }

    if (error is HandshakeException) {
      return 'TLS 握手失败，请检查服务器地址、SNI 和 TLS 设置；如果节点要求，可尝试开启“允许不安全证书”。';
    }

    return 'Failed to update the proxy configuration: $error';
  }
}
