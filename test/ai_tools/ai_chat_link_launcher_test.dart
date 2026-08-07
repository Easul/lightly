import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/ai/ai_chat_link_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  test('opens chat links in an in-app browser view', () async {
    Uri? openedUri;
    LaunchMode? openedMode;
    final launcher = AiChatLinkLauncher(
      openUrl: (uri, mode) async {
        openedUri = uri;
        openedMode = mode;
        return true;
      },
    );

    final result = await launcher.open(Uri.parse('https://example.com/path'));

    expect(result, isTrue);
    expect(openedUri, Uri.parse('https://example.com/path'));
    expect(openedMode, LaunchMode.inAppBrowserView);
  });
}
