import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/life_runtime_config.dart';

class LifeRuntimeConfigStore {
  LifeRuntimeConfigStore({SharedPreferences? preferences})
    : _preferences = preferences;

  static const storageKey = 'life_runtime_config_v1';
  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  Future<LifeRuntimeConfig> load() async {
    final raw = (await _prefs).getString(storageKey);
    if (raw == null || raw.isEmpty) return const LifeRuntimeConfig();
    return LifeRuntimeConfig.fromJson(jsonDecode(raw));
  }

  Future<void> save(LifeRuntimeConfig config) async {
    await (await _prefs).setString(storageKey, config.encode());
  }
}
