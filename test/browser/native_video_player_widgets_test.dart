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
}
