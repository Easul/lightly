import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/models/browser_suggestion.dart';
import 'package:lightly/browser/services/browser_suggestion_service.dart';
import 'package:lightly/browser/widgets/browser_address_bar.dart';

void main() {
  testWidgets('shows title and url and submits the suggestion url', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    String? submittedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: BrowserAddressBar(
              controller: controller,
              focusNode: focusNode,
              isSecure: true,
              suggestionService: _FakeSuggestionService(),
              onChanged: (_) {},
              onSubmitted: (value) => submittedValue = value,
              onClear: () {},
              onEditingComplete: () {},
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.pump();

    expect(find.text('Example title'), findsOneWidget);
    expect(find.text('https://example.com/path'), findsOneWidget);

    await tester.tap(find.text('Example title'));
    await tester.pump();

    expect(submittedValue, 'https://example.com/path');
    expect(controller.text, 'https://example.com/path');

    controller.dispose();
    focusNode.dispose();
  });
}

class _FakeSuggestionService extends BrowserSuggestionService {
  _FakeSuggestionService() : super(debounceDuration: Duration.zero);

  @override
  Future<List<BrowserSuggestion>> suggest(String query) async {
    return <BrowserSuggestion>[
      BrowserSuggestion(
        title: 'Example title',
        url: 'https://example.com/path',
        visitCount: 2,
        visitedAt: DateTime(2026, 7, 15),
      ),
    ];
  }
}
