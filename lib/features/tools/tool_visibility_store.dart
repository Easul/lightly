import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Owns the persisted list of tools that are intentionally hidden by default.
class ToolVisibilityStore {
  static const storageKey = 'tools_hidden_ids_v1';

  static const tg = 'telegram';
  static const chat = 'chat';
  static const remoteControl = 'remote_control';
  static const p2pVpn = 'p2p_vpn';
  static const lifeRuntime = 'life_runtime';
  static const calculator = 'calculator';
  static const translation = 'translation';
  static const music = 'music';
  static const game2048 = 'game_2048';

  static const hiddenByDefault = <String>{
    tg,
    chat,
    remoteControl,
    p2pVpn,
    lifeRuntime,
    calculator,
    translation,
    music,
    game2048,
  };

  Future<Set<String>> loadHiddenIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return {...hiddenByDefault};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {...hiddenByDefault};
      return decoded.whereType<String>().toSet();
    } on FormatException {
      return {...hiddenByDefault};
    }
  }

  Future<void> saveHiddenIds(Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(ids.toSet().toList()..sort()));
  }
}
