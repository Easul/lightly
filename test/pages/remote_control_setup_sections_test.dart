import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/remote_control/presentation/widgets/remote_control_setup_sections.dart';
import 'package:lightly/services/remote_control_service.dart';

void main() {
  testWidgets('receiver no-tun switch shows voice disabled hint', (
    tester,
  ) async {
    var useNoTunMode = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return RemoteControlReceiverSection(
                portConfig: null,
                isReceiverAudioEnabled: false,
                state: RemoteControlState.idle,
                isConnecting: false,
                isReceiverRunning: false,
                useNoTunMode: useNoTunMode,
                onUseNoTunModeChanged: (value) {
                  setState(() => useNoTunMode = value);
                },
                onToggleReceiverMic: () {},
                onToggleReceiver: () {},
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('使用非 VPN 模式'), findsOneWidget);
    expect(find.text('实时通话不可用'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('实时通话不可用'), findsOneWidget);
    expect(find.text('非 VPN 模式会禁用本地与远端开麦'), findsOneWidget);
  });

  testWidgets('controller shows hint when P2P runs no-vpn mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RemoteControlControllerSection(
              peers: const <Map<String, String>>[],
              isEasyTierRunning: true,
              isEasyTierNoTunMode: true,
              isLoadingPeers: false,
              hostController: TextEditingController(),
              controlPortController: TextEditingController(),
              screenPortController: TextEditingController(),
              portConfig: null,
              isConnecting: false,
              useInternalProxy: false,
              isProxyRunning: false,
              onReloadPeers: () {},
              onSelectPeer: (_) {},
              onControlPortChanged: (_) {},
              onScreenPortChanged: (_) {},
              onUseInternalProxyChanged: (_) {},
              onConnect: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('当前 P2P VPN 使用非 VPN 模式，主控端会继续通过非 VPN 模式连接被控端。'),
      findsOneWidget,
    );
  });
}
