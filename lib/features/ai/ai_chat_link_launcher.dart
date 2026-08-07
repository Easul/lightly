import 'package:url_launcher/url_launcher.dart';

typedef AiChatUrlOpener = Future<bool> Function(Uri uri, LaunchMode mode);

class AiChatLinkLauncher {
  const AiChatLinkLauncher({AiChatUrlOpener? openUrl}) : _openUrl = openUrl;

  final AiChatUrlOpener? _openUrl;

  Future<bool> open(Uri uri) {
    final openUrl = _openUrl;
    if (openUrl != null) {
      return openUrl(uri, LaunchMode.inAppBrowserView);
    }
    return launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }
}
