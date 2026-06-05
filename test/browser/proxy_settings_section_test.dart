import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/widgets/settings/proxy_settings_section.dart';

void main() {
  testWidgets('proxy settings shows saved nodes and supports select/delete', (
    tester,
  ) async {
    String? selectedNodeId;
    String? deletedNodeId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProxySettingsSection(
              enabled: true,
              supported: true,
              isSaving: false,
              stateLabel: '未连接',
              stateColor: Colors.grey,
              detailText: '代理地址：proxy.example.com:443',
              nodeLinkController: TextEditingController(),
              proxyNodes: const <BrowserProxyNode>[
                BrowserProxyNode(
                  id: 'node-1',
                  name: '主节点',
                  proxyHost: 'proxy.example.com',
                  proxyPort: 443,
                  proxyScheme: BrowserProxyProtocol.vless,
                  proxyUuid: 'uuid',
                  proxyTlsEnabled: true,
                  proxyTlsInsecure: false,
                  proxyServerName: '',
                  proxyTransportType: '',
                  proxyTransportPath: '',
                  proxyTransportHost: '',
                  proxyPacketEncoding: '',
                ),
              ],
              selectedProxyNodeId: null,
              errorMessage: null,
              selectedProtocol: BrowserProxyProtocol.vless,
              showsUuidField: true,
              showsTransportFields: true,
              showsHysteria2ObfsFields: false,
              showsPacketEncodingField: true,
              showsTlsFields: true,
              proxyTlsEnabled: true,
              selectedTransportType: '',
              proxyPacketEncoding: '',
              proxyTlsInsecure: false,
              proxyHostController: TextEditingController(
                text: 'proxy.example.com',
              ),
              proxyPortController: TextEditingController(text: '443'),
              localProxyPortController: TextEditingController(text: '23333'),
              proxyUuidController: TextEditingController(text: 'uuid'),
              proxyServerNameController: TextEditingController(),
              proxyTransportPathController: TextEditingController(),
              proxyTransportHostController: TextEditingController(),
              proxyBypassDomainsController: TextEditingController(),
              onToggle: (_) {},
              onParse: () async {},
              onTestSpeed: () async {},
              onAddProxyNode: () {},
              onSelectProxyNode: (id) => selectedNodeId = id,
              onDeleteProxyNode: (id) => deletedNodeId = id,
              onConfigurationChanged: () {},
              onProtocolChanged: (_) {},
              onTlsEnabledChanged: (_) {},
              onTransportTypeChanged: (_) {},
              onPacketEncodingChanged: (_) {},
              onTlsInsecureChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('主节点'), findsOneWidget);
    expect(find.text('VLESS · proxy.example.com:443'), findsOneWidget);

    await tester.tap(find.text('主节点'));
    expect(selectedNodeId, 'node-1');

    await tester.tap(find.byTooltip('删除节点'));
    expect(deletedNodeId, 'node-1');
  });
}
