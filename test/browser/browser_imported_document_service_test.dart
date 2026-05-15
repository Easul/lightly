import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/models/browser_favorite.dart';
import 'package:lightly/browser/services/browser_favorite_service.dart';
import 'package:lightly/browser/services/browser_imported_document_service.dart';

void main() {
  test('cleanup retains favorite URLs', () async {
    List<String>? retainedUrls;
    final service = BrowserImportedDocumentService(
      favoriteService: _FakeBrowserFavoriteService(),
      cleanupImportedFiles: (urls) async {
        retainedUrls = urls;
        return true;
      },
    );

    await service.cleanupUnfavoritedImportedFiles();

    expect(retainedUrls, <String>[
      'file:///data/user/0/lightly.tool/files/imported_documents/favorite.txt',
      'https://example.com',
    ]);
  });
}

class _FakeBrowserFavoriteService extends BrowserFavoriteService {
  @override
  Future<List<BrowserFavorite>> query({String? searchTerm}) async {
    return <BrowserFavorite>[
      BrowserFavorite(
        url:
            'file:///data/user/0/lightly.tool/files/imported_documents/favorite.txt',
        title: 'Favorite file',
        createdAt: DateTime.utc(2024, 1, 1),
        sortOrder: 0,
      ),
      BrowserFavorite(
        url: 'https://example.com',
        title: 'Web favorite',
        createdAt: DateTime.utc(2024, 1, 2),
        sortOrder: 1,
      ),
    ];
  }
}
