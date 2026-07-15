import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/models/browser_history_visit.dart';
import 'package:lightly/browser/services/browser_history_service.dart';
import 'package:lightly/pages/browser_history_page.dart';

void main() {
  testWidgets('groups visits by date and shows title with url', (tester) async {
    final now = DateTime.now();
    final service = _FakeHistoryService(<BrowserHistoryVisit>[
      BrowserHistoryVisit(
        id: 1,
        url: 'https://example.com',
        title: 'Example title',
        visitedAt: now,
      ),
      BrowserHistoryVisit(
        id: 2,
        url: 'https://no-title.example',
        title: '',
        visitedAt: now.subtract(const Duration(days: 1)),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: BrowserHistoryPage(historyService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('今天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.text('Example title'), findsOneWidget);
    expect(find.text('https://example.com'), findsOneWidget);
    expect(find.text('https://no-title.example'), findsNWidgets(2));
  });

  testWidgets('long press confirms and deletes one visit', (tester) async {
    final visit = BrowserHistoryVisit(
      id: 3,
      url: 'https://delete.example',
      title: 'Delete me',
      visitedAt: DateTime.now(),
    );
    final service = _FakeHistoryService(<BrowserHistoryVisit>[visit]);

    await tester.pumpWidget(
      MaterialApp(home: BrowserHistoryPage(historyService: service)),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Delete me'));
    await tester.pumpAndSettle();
    expect(find.text('删除这条浏览记录？'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(service.deletedVisits, <BrowserHistoryVisit>[visit]);
    expect(find.text('Delete me'), findsNothing);
  });
}

class _FakeHistoryService extends BrowserHistoryService {
  _FakeHistoryService(this.visits);

  final List<BrowserHistoryVisit> visits;
  final List<BrowserHistoryVisit> deletedVisits = <BrowserHistoryVisit>[];

  @override
  Future<List<BrowserHistoryVisit>> queryVisits({
    String? searchTerm,
    DateTime? beforeVisitedAt,
    int? beforeId,
    int limit = 50,
  }) async {
    return visits.take(limit).toList(growable: false);
  }

  @override
  Future<void> deleteVisit(BrowserHistoryVisit visit) async {
    deletedVisits.add(visit);
    visits.removeWhere((item) => item.id == visit.id);
  }
}
