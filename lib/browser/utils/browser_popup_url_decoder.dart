class BrowserPopupUrlDecoder {
  const BrowserPopupUrlDecoder._();

  static final RegExp _percentEncodedByte = RegExp(r'%[0-9a-fA-F]{2}');

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
}
