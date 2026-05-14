import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'browser_settings.dart';

class BrowserSettingsService {
  static const String _storageKey = 'browser_settings';

  Future<BrowserSettings> loadSettings() async {
    final preferences = await SharedPreferences.getInstance();
    final storedValue = preferences.getString(_storageKey);

    if (storedValue == null || storedValue.isEmpty) {
      return BrowserSettings.defaults();
    }

    final decodedValue = jsonDecode(storedValue) as Map<String, dynamic>;
    return BrowserSettings.fromJson(decodedValue);
  }

  Future<void> saveSettings(BrowserSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    final encodedValue = jsonEncode(settings.toJson());
    await preferences.setString(_storageKey, encodedValue);
  }
}
