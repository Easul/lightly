import '../browser/utils/browser_url_utils.dart';

class BrowserPageInputResolver {
  const BrowserPageInputResolver();

  static bool isDeveloperToolsCommand(String input) {
    final normalized = input.trim().toLowerCase();
    return normalized == 'lightly://devtools' ||
        normalized == 'lightly devtools';
  }

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
