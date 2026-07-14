class BrowserPopupUrlDecoder {
  const BrowserPopupUrlDecoder._();

  static final RegExp _percentEncodedByte = RegExp(r'%[0-9a-fA-F]{2}');
  static final RegExp _schemePattern = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):');

  static String decodeIfNeeded(String url) {
    if (!_percentEncodedByte.hasMatch(url)) {
      return url;
    }

    try {
      return Uri.decodeComponent(url);
    } on ArgumentError {
      return url;
    }
  }

  static String? schemeOf(String url) {
    return _schemePattern.firstMatch(url)?.group(1)?.toLowerCase();
  }

  static String externalLaunchUrl({
    required String rawUrl,
    required String decodedUrl,
  }) {
    final launchUrl = schemeOf(rawUrl) == null ? decodedUrl : rawUrl;
    return _restoreKnownCaseSensitivePayload(launchUrl);
  }

  static String _restoreKnownCaseSensitivePayload(String url) {
    if (schemeOf(url) != 'bankabc') {
      return url;
    }
    return url
        .replaceAll(
          RegExp('jumptosharedproduct', caseSensitive: false),
          'jumpToSharedProduct',
        )
        .replaceAll(RegExp('traffictag', caseSensitive: false), 'trafficTag');
  }
}
