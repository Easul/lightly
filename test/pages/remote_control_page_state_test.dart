import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/remote_control/domain/remote_control_config.dart';
import 'package:lightly/features/remote_control/domain/remote_control_runtime.dart';
import 'package:lightly/pages/remote_control_page.dart';

void main() {
  const ports = RemoteControlPortConfig(controlPort: 18080, screenPort: 18081);

  test('restores VPN receiver running state on page re-entry', () {
    final snapshot = RemoteControlPageStateSnapshot.fromValues(
      currentSelectedMode: RemoteControlMode.controller,
      serviceMode: RemoteControlMode.receiver,
      serviceState: RemoteControlState.idle,
      servicePorts: ports,
      isReceiverHostRunning: true,
      isReceiverNoTunMode: false,
      isLocalAudioEnabled: false,
    );

    expect(snapshot.selectedMode, RemoteControlMode.receiver);
    expect(snapshot.portConfig, ports);
    expect(snapshot.isReceiverRunning, isTrue);
    expect(snapshot.useReceiverNoTunMode, isFalse);
    expect(snapshot.hadConnectedSession, isFalse);
  });

  test('restores no-VPN receiver switch on page re-entry', () {
    final snapshot = RemoteControlPageStateSnapshot.fromValues(
      currentSelectedMode: RemoteControlMode.controller,
      serviceMode: RemoteControlMode.receiver,
      serviceState: RemoteControlState.connected,
      servicePorts: ports,
      isReceiverHostRunning: true,
      isReceiverNoTunMode: true,
      isLocalAudioEnabled: false,
    );

    expect(snapshot.selectedMode, RemoteControlMode.receiver);
    expect(snapshot.isReceiverRunning, isTrue);
    expect(snapshot.useReceiverNoTunMode, isTrue);
    expect(snapshot.hadConnectedSession, isTrue);
  });

  test('p2p no-vpn forces receiver no-vpn mode', () {
    expect(
      resolveReceiverNoTunMode(receiverNoTunMode: false, p2pNoTunMode: true),
      isTrue,
    );
  });

  test('p2p vpn mode preserves receiver no-vpn setting', () {
    expect(
      resolveReceiverNoTunMode(receiverNoTunMode: false, p2pNoTunMode: false),
      isFalse,
    );
    expect(
      resolveReceiverNoTunMode(receiverNoTunMode: true, p2pNoTunMode: false),
      isTrue,
    );
  });
}
