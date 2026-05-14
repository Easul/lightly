class BrowserPopupFilter {
  const BrowserPopupFilter._();

  static const Set<String> _webSchemes = {'http', 'https', 'file', 'content'};
  static const Set<String> _popupImageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.svg',
    '.bmp',
    '.ico',
    '.avif',
  };

  static bool isWebScheme(String? scheme) {
    if (scheme == null) {
      return false;
    }
    return _webSchemes.contains(scheme.toLowerCase());
  }

  static bool shouldSuppressPopupUrl(String? url) {
    if (url == null || url.isEmpty) {
      return true;
    }
    if (url.startsWith('blob:') || url.startsWith('data:')) {
      return true;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }

    final path = uri.path.toLowerCase();
    if (_popupImageExtensions.any(path.endsWith)) {
      return true;
    }

    return uri.host.toLowerCase() == 'linux.do' &&
        path.contains('/user_avatar/');
  }
}
