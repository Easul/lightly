import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/models/browser_favorite.dart';
import 'package:lightly/browser/models/browser_history_entry.dart';
import 'package:lightly/browser/services/browser_backup_service.dart';

void main() {
  test('BrowserBackupData round-trips webStorage entries', () {
    final backup = BrowserBackupData(
      favorites: const [],
      settings: BrowserSettings.defaults(),
      history: const [],
      calculatorHistory: const [],
      clipboardContent: 'hello',
      clipboardPort: 12345,
      cookies: const [
        <String, dynamic>{
          'url': 'https://www.duckcoding.ai',
          'name': 'session',
          'value': 'abc',
        },
      ],
      webStorage: const [
        <String, dynamic>{
          'origin': 'https://www.duckcoding.ai',
          'localStorage': <Map<String, dynamic>>[
            <String, dynamic>{'key': 'user', 'value': '{"id":1}'},
          ],
        },
      ],
      easyTierProfiles: const [],
      selectedEasyTierProfileId: null,
      exportedAt: DateTime.parse('2026-05-25T00:00:00.000Z'),
    );

    final restored = BrowserBackupData.fromJsonString(backup.toJsonString());

    expect(restored.cookies, backup.cookies);
    expect(restored.webStorage, backup.webStorage);
    expect(restored.clipboardPort, 12345);
  });

  test('ImportResult reports restored site storage', () {
    const result = ImportResult(
      favoritesImported: 0,
      historyImported: 0,
      calculatorImported: 0,
      cookiesImported: 2,
      webStorageImported: 1,
      easyTierProfilesImported: 0,
      settingsUpdated: false,
      clipboardUpdated: false,
      restoredOrigins: <String>['https://www.duckcoding.ai'],
    );

    expect(result.toString(), contains('2 个 Cookie'));
    expect(result.toString(), contains('1 个站点存储'));
  });

  test('collectWebStorageOriginsForTesting selects session-cookie origins', () {
    final service = BrowserBackupService();

    final origins = service.collectWebStorageOriginsForTesting(
      history: const <BrowserHistoryEntry>[],
      favorites: const <BrowserFavorite>[],
      homepageUrl: 'https://start.example.com',
      cookies: const [
        <String, dynamic>{'url': 'https://muyuan.do', 'name': 'session'},
        <String, dynamic>{
          'url': 'https://www.duckcoding.ai',
          'name': 'SessionId',
        },
        <String, dynamic>{'url': 'https://static.example.com', 'name': 'token'},
      ],
    );

    expect(origins, isNot(contains('https://start.example.com')));
    expect(origins, contains('https://muyuan.do'));
    expect(origins, contains('https://www.duckcoding.ai'));
    expect(origins, contains('https://new-api.abrdns.com'));
    expect(origins, isNot(contains('https://static.example.com')));
    expect(origins.length, 3);
  });
}
