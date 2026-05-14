import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_long_press_handler.dart';
import 'package:lightly/browser/widgets/browser_long_press_actions_sheet.dart';

void main() {
  group('BrowserLongPressHandler', () {
    late BrowserLongPressHandler handler;

    setUp(() {
      handler = BrowserLongPressHandler();
    });

    test('creates youtube request for youtube urls', () {
      final request = handler.createRequest(
        url: 'https://m.youtube.com/watch?v=abc123',
        type: InAppWebViewHitTestResultType.SRC_ANCHOR_TYPE,
      );

      expect(request, isNotNull);
      expect(request!.isYouTube, isTrue);
      expect(
        request.youtubeTargets!.desktopWatchUrl,
        'https://www.youtube.com/watch?v=abc123',
      );
    });

    test('creates image request for image hit tests', () {
      final request = handler.createRequest(
        url: 'https://example.com/image.jpg',
        type: InAppWebViewHitTestResultType.IMAGE_TYPE,
      );

      expect(request, isNotNull);
      expect(request!.isYouTube, isFalse);
      expect(request.isImage, isTrue);
      expect(request.actionType, LongPressActionType.image);
    });

    test('returns null for unsupported hit tests', () {
      final request = handler.createRequest(
        url: 'https://example.com',
        type: InAppWebViewHitTestResultType.UNKNOWN_TYPE,
      );

      expect(request, isNull);
    });
  });
}
