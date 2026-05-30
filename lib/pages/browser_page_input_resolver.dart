import '../browser/utils/browser_url_utils.dart';

class BrowserPageInputResolver {
  const BrowserPageInputResolver();

  String resolve(String input, {required bool isProxyActive}) {
    final maybeUrl = normalizeBrowserUrl(input);
    if (maybeUrl != null) {
      return maybeUrl;
    }

    final engine = isProxyActive
        ? 'https://www.google.com/search?q='
        : 'https://www.baidu.com/s?wd=';
    return engine + Uri.encodeComponent(input);
  }
}
