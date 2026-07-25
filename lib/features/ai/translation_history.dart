import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TranslationHistoryEntry {
  const TranslationHistoryEntry({
    required this.id,
    required this.source,
    required this.translation,
    required this.targetLanguage,
    required this.createdAt,
  });

  final String id;
  final String source;
  final String translation;
  final String targetLanguage;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'source': source,
    'translation': translation,
    'targetLanguage': targetLanguage,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory TranslationHistoryEntry.fromJson(Map<String, dynamic> json) =>
      TranslationHistoryEntry(
        id: json['id'] as String? ?? '',
        source: json['source'] as String? ?? '',
        translation: json['translation'] as String? ?? '',
        targetLanguage: json['targetLanguage'] as String? ?? '自动',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as num?)?.toInt() ?? 0,
        ),
      );
}

class TranslationHistoryStore {
  static const MethodChannel _channel = MethodChannel('translation_overlay');
  static const String _fallbackKey = 'translation_history';

  Future<List<TranslationHistoryEntry>> list() async {
    if (Platform.isAndroid) {
      final raw = await _channel.invokeListMethod<dynamic>('listHistory');
      return (raw ?? const <dynamic>[])
          .map(
            (item) => TranslationHistoryEntry.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);
    }
    return _loadFallback();
  }

  Future<void> save(TranslationHistoryEntry entry) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('saveHistory', entry.toJson());
      return;
    }
    final history = await _loadFallback();
    history.insert(0, entry);
    await _storeFallback(history);
  }

  Future<void> update(TranslationHistoryEntry entry) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('updateHistory', entry.toJson());
      return;
    }
    final history = await _loadFallback();
    final index = history.indexWhere((item) => item.id == entry.id);
    if (index >= 0) history[index] = entry;
    await _storeFallback(history);
  }

  Future<void> delete(String id) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('deleteHistory', <String, String>{
        'id': id,
      });
      return;
    }
    final history = await _loadFallback()
      ..removeWhere((item) => item.id == id);
    await _storeFallback(history);
  }

  Future<void> clear() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('clearHistory');
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_fallbackKey);
  }

  Future<List<TranslationHistoryEntry>> _loadFallback() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_fallbackKey);
    if (raw == null || raw.isEmpty) return <TranslationHistoryEntry>[];
    return (jsonDecode(raw) as List<dynamic>)
        .map(
          (item) => TranslationHistoryEntry.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<void> _storeFallback(List<TranslationHistoryEntry> history) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _fallbackKey,
      jsonEncode(history.take(200).map((item) => item.toJson()).toList()),
    );
  }
}
