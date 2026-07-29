import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/models/browser_favorite.dart';
import 'package:lightly/browser/models/browser_history_entry.dart';
import 'package:lightly/browser/services/browser_backup_service.dart';
import 'package:lightly/browser/services/browser_cookie_origin_service.dart';
import 'package:lightly/features/easytier/domain/easytier_config.dart';
import 'package:lightly/features/easytier/domain/easytier_network_profile.dart';
import 'package:lightly/features/telegram/telegram_checkin_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      easyTierProfiles: <EasyTierNetworkProfile>[
        EasyTierNetworkProfile(
          id: 'vpn-1',
          name: '家庭网络',
          config: EasyTierConfig(
            instanceName: 'phone',
            networkName: 'home',
            networkSecret: 'secret',
            ipv4: '10.126.126.8',
            peers: const <String>['tcp://peer.example.com:11010'],
            activePeerIndex: 0,
          ),
          createdAt: DateTime.parse('2026-05-20T00:00:00.000Z'),
          updatedAt: DateTime.parse('2026-05-21T00:00:00.000Z'),
        ),
      ],
      selectedEasyTierProfileId: 'vpn-1',
      telegramCheckinConfig: const TelegramCheckinConfig(
        apiId: 12345,
        apiHash: 'test_hash',
        phoneNumber: '+8613800000000',
        targets: <TelegramCheckinTarget>[
          TelegramCheckinTarget(
            id: '1',
            username: '@checkin_bot',
            command: '/checkin',
            enabled: false,
          ),
        ],
      ),
      exportedAt: DateTime.parse('2026-05-25T00:00:00.000Z'),
    );

    final restored = BrowserBackupData.fromJsonString(backup.toJsonString());

    expect(restored.cookies, backup.cookies);
    expect(restored.webStorage, backup.webStorage);
    expect(restored.clipboardPort, 12345);
    expect(restored.selectedEasyTierProfileId, 'vpn-1');
    expect(restored.easyTierProfiles.single.id, 'vpn-1');
    expect(restored.easyTierProfiles.single.config.networkName, 'home');
    expect(restored.easyTierProfiles.single.config.networkSecret, 'secret');
    expect(restored.easyTierProfiles.single.config.peers, const <String>[
      'tcp://peer.example.com:11010',
    ]);
    expect(restored.telegramCheckinConfig.apiId, 12345);
    expect(restored.telegramCheckinConfig.apiHash, 'test_hash');
    expect(restored.telegramCheckinConfig.phoneNumber, '+8613800000000');
    expect(
      restored.telegramCheckinConfig.targets.single.username,
      '@checkin_bot',
    );
    expect(restored.telegramCheckinConfig.targets.single.enabled, isFalse);
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
        <String, dynamic>{
          'url': 'https://linux.do',
          'name': 'linuxdo_oauth_intent',
        },
        <String, dynamic>{'url': 'https://static.example.com', 'name': 'token'},
      ],
    );

    expect(origins, isNot(contains('https://start.example.com')));
    expect(origins, contains('https://muyuan.do'));
    expect(origins, contains('https://www.duckcoding.ai'));
    expect(origins, contains('https://linux.do'));
    expect(origins, contains('https://new-api.abrdns.com'));
    expect(origins, contains('https://free.linggan10s.shop'));
    expect(origins, contains('https://up.x666.me'));
    expect(origins, isNot(contains('https://static.example.com')));
    expect(origins.length, 6);
  });

  test('normalizeCookieLookupUrl keeps path but strips query and fragment', () {
    final service = BrowserBackupService();

    expect(
      service.normalizeCookieLookupUrlForTesting(
        'https://api.dwaiai.com/oauth/callback?code=123#done',
      ),
      'https://api.dwaiai.com/oauth/callback',
    );
    expect(
      service.normalizeCookieLookupUrlForTesting('https://api.picpi.top'),
      'https://api.picpi.top/',
    );
  });

  test(
    'collectCookieUrlsForTesting uses WebView origin index, not history',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final originService = BrowserCookieOriginService(
        preferences: preferences,
      );
      await originService.recordUrl('https://session-only.example.com/account');

      final service = BrowserBackupService(cookieOriginService: originService);

      final urls = await service.collectCookieUrlsForTesting();

      expect(urls, contains('https://session-only.example.com/'));
      expect(urls, contains('https://muyuan.do/'));
      expect(urls, isNot(contains('https://start.example.com/')));
    },
  );
}
