import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_shell_widgets.dart';

void main() {
  testWidgets('freezing WebView keeps child state mounted', (tester) async {
    var disposeCount = 0;
    final statusMessage = ValueNotifier<String>('');

    Widget buildHost({required bool frozen}) {
      return MaterialApp(
        home: Scaffold(
          body: BrowserPageBodySection(
            isFavoritesPage: false,
            favoritesChild: const SizedBox.shrink(),
            webViewChild: _DisposableProbe(
              key: const ValueKey('webview-probe'),
              onDispose: () => disposeCount++,
            ),
            freezeWebViewForOverlay: frozen,
            statusMessage: statusMessage,
            youtubePlayButtonVisible: false,
            onYoutubePlayPressed: () {},
          ),
        ),
      );
    }

    await tester.pumpWidget(buildHost(frozen: false));
    expect(find.byKey(const ValueKey('webview-probe')), findsOneWidget);

    await tester.pumpWidget(buildHost(frozen: true));
    expect(disposeCount, 0);
    expect(
      find.byKey(const ValueKey('webview-probe'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('webview-probe')), findsNothing);

    await tester.pumpWidget(buildHost(frozen: false));
    expect(disposeCount, 0);
    expect(find.byKey(const ValueKey('webview-probe')), findsOneWidget);

    statusMessage.dispose();
  });
}

class _DisposableProbe extends StatefulWidget {
  const _DisposableProbe({super.key, required this.onDispose});

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
    return const SizedBox.expand();
  }
}
