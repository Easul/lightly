import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/models/easytier_config.dart';
import 'package:lightly/widgets/easytier/easytier_sections.dart';

void main() {
  testWidgets('peer list exposes active switch and remark field', (
    tester,
  ) async {
    int? selectedIndex;
    int? remarkIndex;
    String? remarkText;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EasyTierConfigurationSection(
              instanceNameController: TextEditingController(text: 'vpn'),
              networkNameController: TextEditingController(text: 'network'),
              networkSecretController: TextEditingController(),
              dhcp: false,
              ipv4Controller: TextEditingController(text: '10.126.126.2/24'),
              hostnameController: TextEditingController(),
              enableP2p: true,
              noTun: true,
              portMappingPortController: TextEditingController(),
              portMappings: const <EasyTierPortMapping>[
                EasyTierPortMapping(port: 8080, remark: 'NAS'),
              ],
              portMappingsExpanded: true,
              peerController: TextEditingController(),
              peers: const <String>[
                'tcp://first.example.com:11010',
                'tcp://second.example.com:11010',
              ],
              peerRemarks: const <String>['家里', '公司'],
              activePeerIndex: 0,
              onDhcpChanged: (_) {},
              onEnableP2pChanged: (_) {},
              onNoTunChanged: (_) {},
              onPortMappingsExpandedChanged: (_) {},
              onAddPortMapping: () {},
              onRemovePortMapping: (_) {},
              onPortMappingRemarkChanged: (_, _) {},
              onAddPeer: () {},
              onRemovePeer: (_) {},
              onSelectPeer: (index) => selectedIndex = index,
              onPeerRemarkChanged: (index, remark) {
                remarkIndex = index;
                remarkText = remark;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('运行时仅连接已启用的节点，其余节点保留但不会写入运行配置。'), findsOneWidget);
    expect(find.text('tcp://first.example.com:11010'), findsOneWidget);
    expect(find.text('tcp://second.example.com:11010'), findsOneWidget);
    expect(find.text('家里'), findsOneWidget);
    expect(find.text('公司'), findsOneWidget);
    expect(find.text('使用非 VPN 模式'), findsOneWidget);
    expect(find.text('TCP 8080 → 本机 8080'), findsOneWidget);
    expect(find.text('NAS'), findsOneWidget);

    await tester.ensureVisible(find.byType(Switch).last);
    await tester.tap(find.byType(Switch).last);
    expect(selectedIndex, 1);

    await tester.ensureVisible(find.byType(TextFormField).last);
    await tester.enterText(find.byType(TextFormField).last, '备用节点');
    expect(remarkIndex, 1);
    expect(remarkText, '备用节点');
  });
}
