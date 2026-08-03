import 'package:shared_preferences/shared_preferences.dart';

class MusicSettings {
  const MusicSettings({
    required this.apiBaseUrl,
    required this.apiKey,
    required this.quality,
    required this.notificationEnabled,
  });

  final String apiBaseUrl;
  final String apiKey;
  final String quality;
  final bool notificationEnabled;

  MusicSettings copyWith({
    String? apiBaseUrl,
    String? apiKey,
    String? quality,
    bool? notificationEnabled,
  }) {
    return MusicSettings(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      apiKey: apiKey ?? this.apiKey,
      quality: quality ?? this.quality,
      notificationEnabled: notificationEnabled ?? this.notificationEnabled,
    );
  }
}

class MusicSettingsStore {
  const MusicSettingsStore();

  static const String _apiBaseUrlKey = 'music_player_api_base_url_v1';
  static const String _apiKeyKey = 'music_player_api_key_v1';
  static const String _qualityKey = 'music_player_quality_v1';
  static const String _notificationKey = 'music_player_notification_v1';
  Future<MusicSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return MusicSettings(
      apiBaseUrl: preferences.getString(_apiBaseUrlKey) ?? '',
      apiKey: preferences.getString(_apiKeyKey) ?? '',
      quality: preferences.getString(_qualityKey) ?? 'standard',
      notificationEnabled: preferences.getBool(_notificationKey) ?? true,
    );
  }

  Future<void> save(MusicSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      preferences.setString(_apiBaseUrlKey, settings.apiBaseUrl.trim()),
      preferences.setString(_apiKeyKey, settings.apiKey.trim()),
      preferences.setString(_qualityKey, settings.quality),
      preferences.setBool(_notificationKey, settings.notificationEnabled),
    ]);
  }
}
