import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lightly/main.dart';
import 'package:lightly/pages/calculator_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('browser page is the default route', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(browserWebViewEnabled: false));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const Key('browser-address-bar')), findsOneWidget);
  });

  testWidgets('drawer shows browser navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(browserWebViewEnabled: false));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('浏览器'), findsWidgets);
    expect(find.text('小工具'), findsOneWidget);
    expect(find.text('2048'), findsNothing);
    expect(find.text('计算器'), findsNothing);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('tools page navigates to 2048 page', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(browserWebViewEnabled: false));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump(const Duration(milliseconds: 400));
    final toolsTile = tester.widget<ListTile>(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.widgetWithText(ListTile, '小工具'),
      ),
    );
    toolsTile.onTap!.call();
    await tester.pumpAndSettle();
    await tester.tap(find.text('2048'));
    await tester.pumpAndSettle();

    expect(find.text('2048'), findsWidgets);
    expect(find.text('New Game'), findsOneWidget);
  });

  testWidgets('tools page navigates to calculator page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(browserWebViewEnabled: false));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump(const Duration(milliseconds: 400));
    final toolsTile = tester.widget<ListTile>(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.widgetWithText(ListTile, '小工具'),
      ),
    );
    toolsTile.onTap!.call();
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算器'));
    await tester.pumpAndSettle();

    expect(find.text('计算器'), findsWidgets);
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
