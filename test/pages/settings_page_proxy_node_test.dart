import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/pages/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const oldNode = BrowserProxyNode(
    id: 'old-node',
    name: '旧节点',
    proxyHost: 'old.example.com',
    proxyPort: 443,
    proxyScheme: BrowserProxyProtocol.vless,
    proxyUuid: '123e4567-e89b-12d3-a456-426614174000',
    proxyTlsEnabled: true,
    proxyTlsInsecure: false,
    proxyServerName: 'old.example.com',
    proxyTransportType: 'ws',
    proxyTransportPath: '/old',
    proxyTransportHost: 'old.example.com',
    proxyPacketEncoding: '',
  );

  testWidgets(
    'parse and apply appends parsed node instead of replacing selected',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final storedSettings = BrowserSettings.defaults().copyWith(
          proxyEnabled: true,
          proxyHost: oldNode.proxyHost,
          proxyPort: oldNode.proxyPort,
          proxyScheme: oldNode.proxyProtocol,
          proxyUuid: oldNode.proxyUuid,
          proxyTlsEnabled: oldNode.proxyTlsEnabled,
          proxyServerName: oldNode.proxyServerName,
          proxyTransportType: oldNode.proxyTransportType,
          proxyTransportPath: oldNode.proxyTransportPath,
          proxyTransportHost: oldNode.proxyTransportHost,
          proxyNodes: const <BrowserProxyNode>[oldNode],
          selectedProxyNodeId: oldNode.id,
        );
        SharedPreferences.setMockInitialValues({
          'browser_settings': jsonEncode(storedSettings.toJson()),
        });

        await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('代理'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, '粘贴 vless:// 或 http:// 链接'),
          'vless://123e4567-e89b-12d3-a456-426614174000@new.example.com:443?type=ws&path=%2Fnew&host=cdn.example.com&security=tls&sni=new.example.com#新节点',
        );
        await tester.tap(find.text('解析并应用'));
        await tester.pump();

        expect(find.text('旧节点'), findsOneWidget);
        expect(find.text('新节点'), findsOneWidget);
        expect(find.text('VLESS · new.example.com:443'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
