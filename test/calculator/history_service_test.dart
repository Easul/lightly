import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/calculator/calculation_history.dart';
import 'package:lightly/features/calculator/history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('HistoryService', () {
    late HistoryService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = HistoryService();
    });

    test('loadHistory returns empty list when nothing is stored', () async {
      expect(await service.loadHistory(), isEmpty);
    });

    test('saveEntry stores a new entry at the beginning', () async {
      final firstEntry = _entry(id: '1', expression: '1+1', result: '2');
      final secondEntry = _entry(id: '2', expression: '2+2', result: '4');

      await service.saveEntry(firstEntry);
      await service.saveEntry(secondEntry);

      final history = await service.loadHistory();

      expect(history, hasLength(2));
      expect(history.first.id, '2');
      expect(history.last.id, '1');
    });

    test('saveEntry keeps only the latest 100 entries', () async {
      for (var index = 0; index < 101; index++) {
        await service.saveEntry(
          _entry(
            id: '$index',
            expression: '$index+$index',
            result: '${index * 2}',
          ),
        );
      }

      final history = await service.loadHistory();

      expect(history, hasLength(100));
      expect(history.first.id, '100');
      expect(history.last.id, '1');
      expect(history.any((entry) => entry.id == '0'), isFalse);
    });

    test('updateNote updates only the matching entry', () async {
      final firstEntry = _entry(id: '1', expression: '1+1', result: '2');
      final secondEntry = _entry(id: '2', expression: '2+2', result: '4');

      await service.saveEntry(firstEntry);
      await service.saveEntry(secondEntry);
      await service.updateNote('1', 'favorite');

      final history = await service.loadHistory();

      expect(history.first.id, '2');
      expect(history.first.note, isEmpty);
      expect(history.last.id, '1');
      expect(history.last.note, 'favorite');
    });

    test('clearHistory removes all stored entries', () async {
      await service.saveEntry(_entry(id: '1', expression: '1+1', result: '2'));

      await service.clearHistory();

      expect(await service.loadHistory(), isEmpty);
    });
  });
}

CalculationHistory _entry({
  required String id,
  required String expression,
  required String result,
  String note = '',
}) {
  return CalculationHistory(
    id: id,
    expression: expression,
    result: result,
    createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
    note: note,
  );
}
