import 'dart:convert';

import 'package:lightly/calculator/calculation_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryService {
  static const String _storageKey = 'calculation_history';
  static const int _maxEntries = 100;

  Future<List<CalculationHistory>> loadHistory() async {
    final preferences = await SharedPreferences.getInstance();
    final storedHistory = preferences.getString(_storageKey);

    if (storedHistory == null || storedHistory.isEmpty) {
      return [];
    }

    final decodedHistory = jsonDecode(storedHistory) as List<dynamic>;

    return decodedHistory
        .cast<Map<String, dynamic>>()
        .map(CalculationHistory.fromJson)
        .toList();
  }

  Future<void> saveEntry(CalculationHistory entry) async {
    final history = await loadHistory();
    history.insert(0, entry);

    if (history.length > _maxEntries) {
      history.removeRange(_maxEntries, history.length);
    }

    await _storeHistory(history);
  }

  Future<void> updateNote(String id, String note) async {
    final history = await loadHistory();
    final updatedHistory = history
        .map((entry) => entry.id == id ? entry.copyWith(note: note) : entry)
        .toList();

    await _storeHistory(updatedHistory);
  }

  Future<void> clearHistory() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }

  Future<void> _storeHistory(List<CalculationHistory> history) async {
    final preferences = await SharedPreferences.getInstance();
    final encodedHistory = jsonEncode(
      history.map((entry) => entry.toJson()).toList(),
    );

    await preferences.setString(_storageKey, encodedHistory);
  }
}
