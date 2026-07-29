import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/data/app_database.dart';
import 'package:lightly/browser/models/browser_download_record.dart';
import 'package:lightly/browser/services/browser_backup_service.dart';
import 'package:lightly/browser/services/browser_download_store.dart';
import 'package:lightly/browser/services/browser_favorite_service.dart';
import 'package:lightly/features/telegram/telegram_checkin_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late String databasePath;
  AppDatabase? appDatabase;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databasePath = p.join(
      await getDatabasesPath(),
      'browser_backup_downloads_${DateTime.now().microsecondsSinceEpoch}.db',
    );
  });

  tearDown(() async {
    await appDatabase?.close();
    await databaseFactory.deleteDatabase(databasePath);
  });

  test('download import deduplicates and pauses active records', () async {
    appDatabase = AppDatabase.forTesting(databasePath);
    final downloadStore = BrowserDownloadStore(database: appDatabase);
    final service = BrowserBackupService(
      favoriteService: BrowserFavoriteService(database: appDatabase),
      downloadStore: downloadStore,
    );
    final active = BrowserDownloadRecord(
      url: 'https://example.com/file.zip',
      fileName: 'file.zip',
      status: 'downloading',
      savedPath: '/storage/emulated/0/Download/file.zip',
      totalBytes: 100,
      bytesReceived: 40,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1234),
    );
    final backup = BrowserBackupData(
      favorites: const [],
      settings: BrowserSettings.defaults(),
      history: const [],
      downloads: <BrowserDownloadRecord>[active],
      calculatorHistory: const [],
      clipboardContent: '',
      clipboardPort: null,
      cookies: const [],
      webStorage: const [],
      easyTierProfiles: const [],
      selectedEasyTierProfileId: null,
      telegramCheckinConfig: const TelegramCheckinConfig(),
      exportedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final first = await service.importData(
      backup,
      importSettings: false,
      importHistory: false,
      importClipboard: false,
      importCalculatorHistory: false,
      importWebData: false,
      importEasyTierProfiles: false,
    );
    final second = await service.importData(
      backup,
      importSettings: false,
      importHistory: false,
      importClipboard: false,
      importCalculatorHistory: false,
      importWebData: false,
      importEasyTierProfiles: false,
    );

    expect(first.downloadsImported, 1);
    expect(second.downloadsImported, 0);
    final restored = await downloadStore.list(limit: null);
    expect(restored, hasLength(1));
    expect(restored.single.status, 'paused');
    expect(restored.single.bytesReceived, 40);
  });
}
