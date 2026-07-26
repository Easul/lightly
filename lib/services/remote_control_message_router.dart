import 'dart:typed_data';

import 'remote_control_command_helper.dart';
import '../features/remote_control/domain/remote_control_protocol.dart';

class RemoteControlMessageRouter {
  RemoteControlMessageRouter({
    RemoteControlCommandHelper commandHelper =
        const RemoteControlCommandHelper(),
  }) : _commandHelper = commandHelper;

  final RemoteControlCommandHelper _commandHelper;
  final StringBuffer _controllerControlBuffer = StringBuffer();
  final StringBuffer _receiverControlBuffer = StringBuffer();

  List<ControlMessage> decodeControllerMessages(Uint8List data) {
    return _commandHelper.decodeBufferedMessages(
      _controllerControlBuffer,
      data,
    );
  }

  void dispatchReceiverData(
    Uint8List data, {
    required Future<void> Function(String command) executeCommand,
    required int minBitrate,
    required int maxBitrate,
    required void Function(ControlMessage message) recordStatusMessage,
    required void Function(ControlMessage message) emitMessage,
    required Future<void> Function() requestKeyFrame,
    required Future<void> Function(int bitrate) updateBitrate,
    required Future<void> Function(int messageId, bool success, [String? error])
    sendAck,
    required void Function(HeartbeatMessage message) onHeartbeat,
    required Future<void> Function() shutdownReceiver,
    required void Function(String message, {Object? error}) log,
  }) {
    final commands = _commandHelper.decodeBufferedLines(
      _receiverControlBuffer,
      data,
    );
    for (final command in commands) {
      _commandHelper.dispatchReceiverCommand(
        command,
        executeCommand: executeCommand,
        minBitrate: minBitrate,
        maxBitrate: maxBitrate,
        recordStatusMessage: recordStatusMessage,
        emitMessage: emitMessage,
        requestKeyFrame: requestKeyFrame,
        updateBitrate: updateBitrate,
        sendAck: sendAck,
        onHeartbeat: onHeartbeat,
        shutdownReceiver: shutdownReceiver,
        log: log,
      );
    }
  }

  void resetController() {
    _controllerControlBuffer.clear();
  }

  void resetReceiver() {
    _receiverControlBuffer.clear();
  }

  void resetAll() {
    resetController();
    resetReceiver();
  }
}
