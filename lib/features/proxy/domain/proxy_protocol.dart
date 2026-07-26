class BrowserProxyProtocol {
  static const String http = 'http';
  static const String vless = 'vless';
  static const String hysteria2 = 'hysteria2';

  static const List<String> values = [http, vless, hysteria2];

  static String normalize(String? value) {
    final normalizedValue = (value ?? '').trim().toLowerCase().replaceFirst(
      RegExp(r':/*$'),
      '',
    );

    switch (normalizedValue) {
      case 'http':
      case 'https':
        return http;
      case vless:
        return vless;
      case 'hy2':
      case hysteria2:
        return hysteria2;
      default:
        return http;
    }
  }

  static String label(String protocol) {
    switch (normalize(protocol)) {
      case http:
        return 'HTTP';
      case vless:
        return 'VLESS';
      case hysteria2:
        return 'Hysteria2';
    }

    return 'HTTP';
  }
}
