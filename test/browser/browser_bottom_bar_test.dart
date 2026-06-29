import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightly/browser/widgets/browser_bottom_bar.dart';
import 'package:lightly/browser/widgets/browser_more_actions_sheet.dart';

void main() {
  Widget buildBottomBar({
    VoidCallback? onNewTab,
    VoidCallback? onCloseTab,
    VoidCallback? onOpenTabs,
    VoidCallback? onOpenMoreActions,
  }) {
    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: BrowserBottomBar(
          canGoBack: true,
          canGoForward: true,
          isLoading: false,
          tabCount: 3,
          proxyEnabled: false,
          onBack: () {},
          onForward: () {},
          onHome: () {},
          onOpenTabs: onOpenTabs ?? () {},
          onOpenMoreActions: onOpenMoreActions ?? () {},
        ),
      ),
    );
  }

  testWidgets('back button triggers callback', (WidgetTester tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: BrowserBottomBar(
            canGoBack: true,
            canGoForward: false,
            isLoading: false,
            tabCount: 1,
            proxyEnabled: false,
            onBack: () => tapped = true,
            onForward: () {},
            onHome: () {},
            onOpenTabs: () {},
            onOpenMoreActions: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('后退'));

    expect(tapped, isTrue);
  });

  testWidgets('forward button is disabled when canGoForward is false', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: BrowserBottomBar(
            canGoBack: false,
            canGoForward: false,
            isLoading: false,
            tabCount: 1,
            proxyEnabled: false,
            onBack: () {},
            onForward: () {},
            onHome: () {},
            onOpenTabs: () {},
            onOpenMoreActions: () {},
          ),
        ),
      ),
    );

    final forwardButton = find.byTooltip('前进');
    expect(forwardButton, findsOneWidget);

    final inkWell = tester.widget<InkWell>(
      find.descendant(of: forwardButton, matching: find.byType(InkWell)),
    );
    expect(inkWell.onTap, isNull);
  });

  testWidgets('home button shows home icon', (WidgetTester tester) async {
    await tester.pumpWidget(buildBottomBar());

    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
  });

  testWidgets('more button shows more icon when loading', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: BrowserBottomBar(
            canGoBack: true,
            canGoForward: true,
            isLoading: true,
            tabCount: 1,
            proxyEnabled: false,
            onBack: () {},
            onForward: () {},
            onHome: () {},
            onOpenTabs: () {},
            onOpenMoreActions: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
  });

  testWidgets('tab counter button triggers callback', (
    WidgetTester tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(buildBottomBar(onOpenTabs: () => tapped = true));

    await tester.tap(find.byTooltip('标签页'));

    expect(tapped, isTrue);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('uses content-driven height on normal phone screens', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildBottomBar());

    expect(tester.getSize(find.byType(BrowserBottomBar)).height, 60);
  });

  testWidgets('uses compact height on narrow screens', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildBottomBar());

    expect(tester.getSize(find.byType(BrowserBottomBar)).height, 56);
  });

  testWidgets('more button triggers callback', (WidgetTester tester) async {
    var tapped = false;

    await tester.pumpWidget(
      buildBottomBar(onOpenMoreActions: () => tapped = true),
    );

    await tester.tap(find.byTooltip('更多'));

    expect(tapped, isTrue);
  });

  testWidgets('BrowserMoreActionsSheet shows actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (_) => BrowserMoreActionsSheet(
                      proxyEnabled: false,
                      desktopModeEnabled: false,
                      webDebugConsoleEnabled: false,
                      isFavorited: false,
                      onToggleFavorite: () {},
                      onToggleProxy: () {},
                      onToggleWebDebugConsole: () {},
                      onToggleDesktopMode: () {},
                      onOpenDownloads: () {},
                      onOpenDataManagement: () {},
                      onCloseTab: () {},
                      onOpenSettings: () {},
                      onEnterFloatingWindowMode: () {},
                      onExitApp: () {},
                    ),
                  );
                },
                child: const Text('Show'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('添加收藏'), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('数据管理'), findsOneWidget);
    expect(find.text('关闭标签页'), findsOneWidget);
    expect(find.text('开启页面调试台'), findsOneWidget);
    expect(find.text('电脑模式'), findsOneWidget);
    expect(find.text('页面内查找'), findsNothing);
    expect(find.text('设置'), findsOneWidget);
  });
}
