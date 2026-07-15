class BrowserForceRefreshCoordinator {
  const BrowserForceRefreshCoordinator();

  Future<String?> refresh({
    required String fallbackUrl,
    required Future<void> Function() stopLoading,
    required Future<String?> Function() readCurrentUrl,
    required Future<void> Function(String url) loadUrl,
  }) async {
    await stopLoading();

    String? controllerUrl;
    try {
      controllerUrl = await readCurrentUrl();
    } catch (_) {}
    final targetUrl = _firstUsableUrl(controllerUrl, fallbackUrl);
    if (targetUrl == null) {
      return null;
    }

    await loadUrl(targetUrl);
    return targetUrl;
  }

  String? _firstUsableUrl(String? primary, String fallback) {
    for (final candidate in <String?>[primary, fallback]) {
      final normalized = candidate?.trim() ?? '';
      if (_isUsableUrl(normalized)) {
        return normalized;
      }
    }
    return null;
  }

  bool _isUsableUrl(String url) {
    if (url.isEmpty) {
      return false;
    }
    final scheme = Uri.tryParse(url)?.scheme.toLowerCase() ?? '';
    return scheme != 'about' && scheme != 'chrome-error';
  }
}
