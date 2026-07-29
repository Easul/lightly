import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/optional_plugin_download_settings.dart';

class OptionalPluginDownloadSettingsStore {
  OptionalPluginDownloadSettingsStore({SharedPreferences? preferences})
    : _preferences = preferences;

  static const String storageKey = 'optional_plugin_download_settings_v1';

  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  Future<OptionalPluginDownloadSettings> load() async {
    final raw = (await _prefs).getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return const OptionalPluginDownloadSettings();
    }
    try {
      return OptionalPluginDownloadSettings.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return const OptionalPluginDownloadSettings();
    }
  }

  Future<void> save(OptionalPluginDownloadSettings settings) async {
    final validationError = settings.validationError;
    if (validationError != null) {
      throw ArgumentError(validationError);
    }
    await (await _prefs).setString(storageKey, jsonEncode(settings.toJson()));
  }
}
