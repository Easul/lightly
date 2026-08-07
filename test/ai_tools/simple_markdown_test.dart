import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/ai/simple_markdown.dart';

void main() {
  testWidgets('renders code metadata, ordered lists, tables, and links', (
    tester,
  ) async {
    String? openedUrl;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SimpleMarkdown('''
1. first

| Name | Value |
| --- | --- |
| A | 1 |

```dart
void main() {}
```

[OpenAI](https://openai.com)
''', onLinkTap: (url) => openedUrl = url),
          ),
        ),
      ),
    );

    expect(find.text('1.'), findsOneWidget);
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('dart'), findsOneWidget);
    expect(find.byTooltip('复制代码'), findsOneWidget);
    expect(find.text('OpenAI'), findsOneWidget);

    await tester.tap(find.text('OpenAI'));
    expect(openedUrl, 'https://openai.com');
  });
}
