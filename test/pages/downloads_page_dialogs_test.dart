import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/downloads_page_dialogs.dart';

void main() {
  testWidgets('download delete dialog offers record-only and file deletion', (
    tester,
  ) async {
    DownloadDeleteChoice? choice;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                choice = await showDownloadDeleteDialog(
                  context,
                  fileName: 'archive.zip',
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('仅删除记录'), findsOneWidget);
    expect(find.text('删除记录和文件'), findsOneWidget);
    expect(find.text('保留设备中的文件'), findsOneWidget);

    await tester.tap(find.text('删除记录和文件'));
    await tester.pumpAndSettle();

    expect(choice, DownloadDeleteChoice.recordAndFile);
  });
}
