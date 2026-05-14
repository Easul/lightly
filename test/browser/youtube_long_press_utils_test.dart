import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/utils/youtube_long_press_utils.dart';

void main() {
  group('deriveYouTubeLongPressTargets', () {
    test('derives from mobile watch url', () {
      final targets = deriveYouTubeLongPressTargets(
        'https://m.youtube.com/watch?v=M7lc1UVf-VE',
      );

      expect(targets, isNotNull);
      expect(targets!.videoId, 'M7lc1UVf-VE');
      expect(
        targets.mobileWatchUrl,
        'https://m.youtube.com/watch?v=M7lc1UVf-VE',
      );
      expect(
        targets.desktopWatchUrl,
        'https://www.youtube.com/watch?v=M7lc1UVf-VE',
      );
      expect(
        targets.thumbnailUrl,
        'https://i.ytimg.com/vi/M7lc1UVf-VE/hqdefault.jpg',
      );
    });

    test('derives from short url', () {
      final targets = deriveYouTubeLongPressTargets(
        'https://youtu.be/M7lc1UVf-VE',
      );

      expect(targets, isNotNull);
      expect(targets!.videoId, 'M7lc1UVf-VE');
    });

    test('derives from shorts url', () {
      final targets = deriveYouTubeLongPressTargets(
        'https://www.youtube.com/shorts/M7lc1UVf-VE',
      );

      expect(targets, isNotNull);
      expect(targets!.videoId, 'M7lc1UVf-VE');
    });

    test('derives from embed url', () {
      final targets = deriveYouTubeLongPressTargets(
        'https://www.youtube.com/embed/M7lc1UVf-VE',
      );

      expect(targets, isNotNull);
      expect(targets!.videoId, 'M7lc1UVf-VE');
    });

    test('derives from thumbnail url', () {
      final targets = deriveYouTubeLongPressTargets(
        'https://i.ytimg.com/vi/M7lc1UVf-VE/hqdefault.jpg',
      );

      expect(targets, isNotNull);
      expect(targets!.videoId, 'M7lc1UVf-VE');
    });

    test('derives from vi_webp thumbnail url', () {
      final targets = deriveYouTubeLongPressTargets(
        'https://i.ytimg.com/vi_webp/M7lc1UVf-VE/hqdefault.webp',
      );

      expect(targets, isNotNull);
      expect(targets!.videoId, 'M7lc1UVf-VE');
    });

    test('derives from an_webp animated thumbnail url', () {
      final targets = deriveYouTubeLongPressTargets(
        'https://i.ytimg.com/an_webp/M7lc1UVf-VE/mqdefault_6s.webp?du=3000&sqp=test',
      );

      expect(targets, isNotNull);
      expect(targets!.videoId, 'M7lc1UVf-VE');
    });

    test('derives from img.youtube.com thumbnail url', () {
      final targets = deriveYouTubeLongPressTargets(
        'https://img.youtube.com/vi/M7lc1UVf-VE/hq720.jpg',
      );

      expect(targets, isNotNull);
      expect(targets!.videoId, 'M7lc1UVf-VE');
    });

    test('derives from numbered ytimg host thumbnail url', () {
      final targets = deriveYouTubeLongPressTargets(
        'https://i9.ytimg.com/vi/M7lc1UVf-VE/hqdefault.jpg?sqp=test',
      );

      expect(targets, isNotNull);
      expect(targets!.videoId, 'M7lc1UVf-VE');
    });

    test('returns null for non-youtube url', () {
      final targets = deriveYouTubeLongPressTargets(
        'https://example.com/image.jpg',
      );

      expect(targets, isNull);
    });
  });
}
