import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClipboardStorageService {
  static const String _contentKey = 'clipboard_content';
  static const String _serverEnabledKey = 'clipboard_server_enabled';
  static const String _serverPortKey = 'clipboard_server_port';

  Future<String> loadContent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_contentKey) ?? '';
  }

  Future<void> saveContent(String text) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentKey, text);
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> clearContent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_contentKey);
    await Clipboard.setData(const ClipboardData(text: ''));
  }

  Future<bool> loadServerEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_serverEnabledKey) ?? true;
  }

  Future<void> saveServerEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_serverEnabledKey, enabled);
  }

  Future<int?> loadServerPort() async {
    final prefs = await SharedPreferences.getInstance();
    final port = prefs.getInt(_serverPortKey);
    return (port != null && port > 0) ? port : 12345;
  }

  Future<void> saveServerPort(int? port) async {
    final prefs = await SharedPreferences.getInstance();
    if (port == null || port <= 0) {
      await prefs.remove(_serverPortKey);
    } else {
      await prefs.setInt(_serverPortKey, port);
    }
  }
}
