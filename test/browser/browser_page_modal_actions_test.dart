import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/models/browser_tab_session.dart';
import 'package:lightly/browser/widgets/browser_more_actions_sheet.dart';
import 'package:lightly/browser/widgets/tab_switcher_sheet.dart';
import 'package:lightly/pages/browser_page_modal_actions.dart';

void main() {
  testWidgets('tab action waits for sheet dismissal animation', (tester) async {
    var selectedTabId = '';
    bool? sheetWasVisibleWhenSelected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () {
                showBrowserTabSwitcherModal(
                  context: context,
                  tabs: const <BrowserTabSession>[
                    BrowserTabSession(
                      id: 'tab-1',
                      url: 'https://example.com',
                      title: 'Example',
                    ),
                  ],
                  activeTabId: 'tab-1',
                  onSelectTab: (tabId) {
                    selectedTabId = tabId;
                    sheetWasVisibleWhenSelected = find
                        .byType(TabSwitcherSheet)
                        .evaluate()
                        .isNotEmpty;
                  },
                  onCloseTab: (_) {},
                  onCloseAll: () {},
                  onNewTab: () {},
                );
              },
              child: const Text('Show tabs'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show tabs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example'));
    await tester.pumpAndSettle();

    expect(selectedTabId, 'tab-1');
    expect(sheetWasVisibleWhenSelected, isFalse);
  });

  testWidgets('more action waits for sheet dismissal animation', (
    tester,
  ) async {
    var openedDownloads = false;
    bool? sheetWasVisibleWhenOpened;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () {
                showBrowserMoreActionsModal(
                  context: context,
                  proxyEnabled: false,
                  desktopModeEnabled: false,
                  webDebugConsoleEnabled: false,
                  isFavorited: false,
                  onToggleFavorite: () {},
                  onToggleProxy: () {},
                  onToggleWebDebugConsole: () {},
                  onToggleDesktopMode: () {},
                  onOpenDownloads: () {
                    openedDownloads = true;
                    sheetWasVisibleWhenOpened = find
                        .byType(BrowserMoreActionsSheet)
                        .evaluate()
                        .isNotEmpty;
                  },
                  onOpenTools: () {},
                  onCloseTab: () {},
                  onOpenSettings: () {},
                  onEnterFloatingWindowMode: () {},
                  onExitApp: () {},
                  onOpenFavoritesMenu: null,
                );
              },
              child: const Text('Show more'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();

    expect(openedDownloads, isTrue);
    expect(sheetWasVisibleWhenOpened, isFalse);
  });

  testWidgets('open sheet releases its animation when host is disposed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () {
                showBrowserTabSwitcherModal(
                  context: context,
                  tabs: const <BrowserTabSession>[],
                  activeTabId: null,
                  onSelectTab: (_) {},
                  onCloseTab: (_) {},
                  onCloseAll: () {},
                  onNewTab: () {},
                );
              },
              child: const Text('Show tabs'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show tabs'));
    await tester.pumpAndSettle();
    expect(find.byType(TabSwitcherSheet), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
