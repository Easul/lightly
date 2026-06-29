import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/clipboard_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = SystemChannels.platform;
  late List<MethodCall> clipboardCalls;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'clipboard_content': 'saved from web',
      'clipboard_server_enabled': false,
      'clipboard_server_port': 12345,
    });
    clipboardCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method.startsWith('Clipboard.')) {
            clipboardCalls.add(call);
          }
          if (call.method == 'Clipboard.getData') {
            return <String, Object?>{'text': 'system clipboard'};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'refresh reloads saved content without reading system clipboard',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ClipboardPage()));
      await tester.pumpAndSettle();

      final editor = tester
          .widgetList<TextField>(find.byType(TextField))
          .firstWhere((field) => field.maxLines == null);
      final controller = editor.controller!;
      expect(controller.text, 'saved from web');

      controller.text = 'local edits';
      await tester.pump();
      clipboardCalls.clear();

      await tester.ensureVisible(find.text('刷新已保存内容'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('刷新已保存内容'));
      await tester.pumpAndSettle();

      expect(controller.text, 'saved from web');
      expect(
        clipboardCalls.where((call) => call.method == 'Clipboard.getData'),
        isEmpty,
      );
    },
  );
}
