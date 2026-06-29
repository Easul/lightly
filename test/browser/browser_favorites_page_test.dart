import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/widgets/browser_favorites_page.dart';

void main() {
  group('defaultBrowserFavoritesInputResolver', () {
    test('normalizes direct urls', () {
      expect(
        defaultBrowserFavoritesInputResolver('example.com'),
        'https://example.com',
      );
    });

    test('falls back to google search for plain keywords', () {
      expect(
        defaultBrowserFavoritesInputResolver('hello world'),
        'https://www.google.com/search?q=hello%20world',
      );
    });
  });
}
