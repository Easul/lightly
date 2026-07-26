import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'telegram_checkin_models.dart';

class TelegramCheckinStore {
  static const String storageKey = 'telegram_checkin_config';

  Future<TelegramCheckinConfig> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return const TelegramCheckinConfig();
    }
    return TelegramCheckinConfig.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  Future<void> save(TelegramCheckinConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(storageKey, jsonEncode(config.toJson()));
  }
}
