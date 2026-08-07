import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lightly/main.dart';
import 'package:lightly/pages/calculator_page.dart';

void useTallTestView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = '${await getDatabasesPath()}/browser_data.db';
    await databaseFactory.deleteDatabase(path);
  });

  testWidgets('browser page is the default route', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(browserWebViewEnabled: false));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const Key('browser-address-bar')), findsOneWidget);
  });

  testWidgets('browser more menu exposes tools without drawer', (
    WidgetTester tester,
  ) async {
    useTallTestView(tester);
    await tester.pumpWidget(const MyApp(browserWebViewEnabled: false));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(Drawer), findsNothing);
    expect(find.byIcon(Icons.menu), findsNothing);

    await tester.tap(find.byTooltip('更多'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('小工具'));
    await tester.pump();

    expect(find.text('小工具'), findsOneWidget);
  });

  testWidgets('tools page navigates to 2048 page', (WidgetTester tester) async {
    useTallTestView(tester);
    await tester.pumpWidget(const MyApp(browserWebViewEnabled: false));
    await tester.pump(const Duration(milliseconds: 600));

    unawaited(
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/tools'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.ensureVisible(find.text('2048'));
    await tester.pump();
    await tester.tap(find.text('2048'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('2048'), findsWidgets);
    expect(find.text('New Game'), findsOneWidget);
  });

  testWidgets('tools page navigates to calculator page', (
    WidgetTester tester,
  ) async {
    useTallTestView(tester);
    await tester.pumpWidget(const MyApp(browserWebViewEnabled: false));
    await tester.pump(const Duration(milliseconds: 600));

    unawaited(
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/tools'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.ensureVisible(find.text('计算器'));
    await tester.pump();
    await tester.tap(find.text('计算器'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('计算器'), findsWidgets);
  });

  testWidgets('tools page groups migrated utility entries', (
    WidgetTester tester,
  ) async {
    useTallTestView(tester);
    await tester.pumpWidget(const MyApp(browserWebViewEnabled: false));
    await tester.pump(const Duration(milliseconds: 600));

    unawaited(
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/tools'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('通讯与协作'), findsOneWidget);
    expect(find.text('网络与文件'), findsOneWidget);
    expect(find.text('日常工具'), findsOneWidget);
    expect(find.text('剪贴板'), findsOneWidget);
    expect(find.text('远程控制'), findsOneWidget);
    expect(find.text('聊天工具'), findsOneWidget);
    expect(find.text('HTTP 文件'), findsOneWidget);
    expect(find.text('文件管理'), findsOneWidget);
    expect(find.text('P2P VPN'), findsOneWidget);
    expect(find.text('翻译工具'), findsOneWidget);
    expect(find.text('时间悬浮窗'), findsOneWidget);
  });

  testWidgets('settings owns data management entry', (
    WidgetTester tester,
  ) async {
    useTallTestView(tester);
    await tester.pumpWidget(const MyApp(browserWebViewEnabled: false));
    await tester.pump(const Duration(milliseconds: 600));

    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('/settings'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('数据管理'), findsOneWidget);
    expect(find.text('本地 HTTP 文件服务'), findsNothing);
    expect(find.text('文件简易管理'), findsNothing);
    expect(find.text('P2P VPN'), findsNothing);
    expect(find.text('远程控制'), findsNothing);
  });

  testWidgets('local HTTP settings route opens the service section directly', (
    WidgetTester tester,
  ) async {
    useTallTestView(tester);
    await tester.pumpWidget(const MyApp(browserWebViewEnabled: false));
    await tester.pump(const Duration(milliseconds: 600));

    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('/local-http-settings'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('本地 HTTP 文件服务'), findsOneWidget);
    expect(find.text('启用本地 HTTP 文件服务'), findsOneWidget);
  });

  testWidgets('local HTTP settings can add and select a favorite root path', (
    WidgetTester tester,
  ) async {
    useTallTestView(tester);
    await tester.pumpWidget(const MyApp(browserWebViewEnabled: false));
    await tester.pump(const Duration(milliseconds: 600));

    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('/local-http-settings'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    await tester.tap(find.text('启用本地 HTTP 文件服务'));
    await tester.pump();
    final rootPathField = find.byType(TextField).first;
    await tester.enterText(rootPathField, '/tmp/site/');
    await tester.tap(find.text('收藏当前路径'));
    await tester.pump();

    expect(find.text('/tmp/site'), findsOneWidget);
    await tester.tap(find.text('/tmp/site'));
    await tester.pump();
    expect(
      tester.widget<TextField>(rootPathField).controller!.text,
      '/tmp/site',
    );
  });

  testWidgets('calculator keypad inserts at the current cursor position', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CalculatorPage()));
    await tester.pumpAndSettle();

    final expressionField = find.byType(TextField).first;
    await tester.enterText(expressionField, '12');
    await tester.pump();

    final fieldWidget = tester.widget<TextField>(expressionField);
    final controller = fieldWidget.controller!;
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, '3'));
    await tester.pump();

    expect(controller.text, '132');
    expect(controller.selection.baseOffset, 2);
  });

  testWidgets(
    'calculator layout stays stable on short screens after showing result',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 520);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: CalculatorPage()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '1+1');
      await tester.tap(find.widgetWithText(ElevatedButton, '='));
      await tester.pumpAndSettle();

      expect(find.text('结果:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
