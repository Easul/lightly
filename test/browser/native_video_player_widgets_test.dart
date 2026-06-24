import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/native_video_player_widgets.dart';

void main() {
  testWidgets('error view exposes close button', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: NativeVideoErrorView(
            message: '播放失败',
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    expect(find.text('播放失败'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    expect(closed, isTrue);
  });

  testWidgets('error view close button falls back to navigator pop', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const Scaffold(
                        backgroundColor: Colors.black,
                        body: NativeVideoErrorView(message: '播放失败'),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('播放失败'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('播放失败'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  group('NativeVideoDialogHeader', () {
    testWidgets('shows parser title with one-line ellipsis rules', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NativeVideoDialogHeader(title: 'Example video title'),
          ),
        ),
      );

      final titleFinder = find.text('Example video title');
      expect(titleFinder, findsOneWidget);
      final title = tester.widget<Text>(titleFinder);
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('falls back to generic title without parser title', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NativeVideoDialogHeader())),
      );

      expect(find.text('视频播放'), findsOneWidget);
    });

    testWidgets('shows loop toggle and invokes callback', (tester) async {
      var toggled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeVideoDialogHeader(
              title: 'Example video title',
              loopingEnabled: true,
              onToggleLooping: () => toggled = true,
            ),
          ),
        ),
      );

      expect(find.text('循环'), findsOneWidget);
      await tester.tap(find.text('循环'));
      await tester.pump();
      expect(toggled, isTrue);
    });
  });
}
