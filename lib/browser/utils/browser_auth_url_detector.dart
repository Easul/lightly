import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class BrowserAuthUrlDetector {
  const BrowserAuthUrlDetector._();

  static const Set<String> _trustedAuthHosts = {
    'accounts.google.com',
    'login.microsoftonline.com',
    'appleid.apple.com',
  };

  static bool isTrustedAuthPopupUrl(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase();
    if (host == null || host.isEmpty) {
      return false;
    }
    final looksLikeAuthFlow = looksLikeAuthUrl(url);
    return _trustedAuthHosts.contains(host) ||
        host.endsWith('.google.com') ||
        host.endsWith('.googleusercontent.com') ||
        host.endsWith('.microsoftonline.com') ||
        host == 'oauth.telegram.org' ||
        host.endsWith('.telegram.org') ||
        looksLikeAuthFlow;
  }

  static bool looksLikeAuthUrl(String? url) {
    if (url == null || url.isEmpty) {
      return false;
    }
    final normalizedUrl = url.toLowerCase();
    final uri = Uri.tryParse(normalizedUrl);
    final path = uri?.path.toLowerCase() ?? '';
    final query = uri?.query.toLowerCase() ?? '';
    return path.contains('login') ||
        path.contains('signin') ||
        path.contains('oauth') ||
        path.contains('authorize') ||
        path.contains('auth') ||
        query.contains('telegram') ||
        normalizedUrl.contains('oauth.telegram.org');
  }

  static bool shouldAllowDeferredAuthPopup(
    CreateWindowAction createWindowAction, {
    required String? currentUrl,
  }) {
    if (createWindowAction.hasGesture != true) {
      return false;
    }
    if (looksLikeAuthUrl(currentUrl)) {
      return true;
    }

    final sourceUrl = createWindowAction.sourceFrame?.request?.url?.toString();
    return looksLikeAuthUrl(sourceUrl);
  }
}
