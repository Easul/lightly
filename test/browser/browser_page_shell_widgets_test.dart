import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_shell_widgets.dart';

void main() {
  testWidgets('YouTube resolve control is an icon-only rounded square', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              BrowserYoutubePlayBubble(visible: true, onPressed: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('解析播放'), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    final ink = tester.widget<Ink>(find.byType(Ink));
    expect(ink.width, 52);
    expect(ink.height, 52);
    final decoration = ink.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(16));
  });

  testWidgets('freezing WebView keeps child mounted and attached', (
    tester,
  ) async {
    var disposeCount = 0;
    var buildCount = 0;
    final statusMessage = ValueNotifier<String>('');
    final freezeWebView = ValueNotifier<bool>(false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrowserPageBodySection(
            isFavoritesPage: false,
            favoritesChild: const SizedBox.shrink(),
            webViewChild: _DisposableProbe(
              key: const ValueKey('webview-probe'),
              onBuild: () => buildCount++,
              onDispose: () => disposeCount++,
            ),
            freezeWebViewForOverlay: freezeWebView,
            statusMessage: statusMessage,
            youtubePlayButtonVisible: false,
            onYoutubePlayPressed: () {},
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('webview-probe')), findsOneWidget);
    expect(buildCount, 1);

    freezeWebView.value = true;
    await tester.pump();
    expect(disposeCount, 0);
    expect(buildCount, 1);
    expect(find.byKey(const ValueKey('webview-probe')), findsOneWidget);
    expect(
      tester
          .widget<IgnorePointer>(
            find.byKey(const ValueKey('browserWebViewOverlayPointerBlocker')),
          )
          .ignoring,
      isTrue,
    );

    freezeWebView.value = false;
    await tester.pump();
    expect(disposeCount, 0);
    expect(buildCount, 1);
    expect(find.byKey(const ValueKey('webview-probe')), findsOneWidget);

    freezeWebView.dispose();
    statusMessage.dispose();
  });
}

class _DisposableProbe extends StatefulWidget {
  const _DisposableProbe({
    super.key,
    required this.onBuild,
    required this.onDispose,
  });

  final VoidCallback onBuild;
  final VoidCallback onDispose;

  @override
  State<_DisposableProbe> createState() => _DisposableProbeState();
}

class _DisposableProbeState extends State<_DisposableProbe> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return const SizedBox.expand();
  }
}
