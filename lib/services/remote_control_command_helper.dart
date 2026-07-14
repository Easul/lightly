import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'remote_control_protocol.dart';

class RemoteControlCommandHelper {
  const RemoteControlCommandHelper();

  List<ControlMessage> decodeBufferedMessages(
    StringBuffer buffer,
    Uint8List data,
  ) {
    final messages = <ControlMessage>[];
    for (final line in decodeBufferedLines(buffer, data)) {
      final message = RemoteControlCodec.decode(line);
      if (message != null) {
        messages.add(message);
      }
    }
    return messages;
  }

  List<String> decodeBufferedLines(StringBuffer buffer, Uint8List data) {
    buffer.write(utf8.decode(data, allowMalformed: true));
    final payload = buffer.toString();
    final lines = payload.split('\n');
    buffer.clear();
    if (lines.isNotEmpty) {
      buffer.write(lines.removeLast());
    }
    return lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  void dispatchReceiverCommand(
    String command, {
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
    try {
      final decoded = jsonDecode(command);
      if (decoded is! Map<String, dynamic>) return;

      final message = ControlMessage.fromJson(decoded);
      if (message is StatusMessage) {
        if (message.action == 'request_key_frame') {
          requestKeyFrame();
          return;
        }
        if (message.action == 'update_bitrate') {
          final bitrate = (message.data['bitrate'] as num?)?.toInt();
          if (bitrate != null && bitrate > 0) {
            updateBitrate(bitrate.clamp(minBitrate, maxBitrate));
          }
          return;
        }
        if (message.action == 'overlay_text') {
          executeCommand(command).catchError((Object error) {
            log('Failed to show receiver overlay text: $error');
          });
          return;
        }
        if (message.action == 'annotation_circle') {
          log(
            'Forwarding receiver annotation circle to native: data=${message.data}',
          );
          executeCommand(command).catchError((Object error) {
            log('Failed to show receiver annotation circle: $error');
          });
          return;
        }
        if (message.action == 'wake_screen') {
          executeCommand(command).catchError((Object error) {
            log('Failed to wake receiver screen: $error');
          });
          return;
        }
        if (message.action == 'shutdown_receiver') {
          unawaited(shutdownReceiver());
          return;
        }
        recordStatusMessage(message);
        emitMessage(message);
        return;
      }

      final type = decoded['type'] as String?;
      if (type == 'heartbeat') {
        final heartbeat = HeartbeatMessage.fromJson(decoded);
        onHeartbeat(heartbeat);
        emitMessage(heartbeat);
        sendAck(heartbeat.id, true);
        return;
      }

      if (type == 'gesture' || type == 'keyboard' || type == 'global') {
        executeCommand(command).catchError((Object error) {
          log('Failed to execute receiver command: $error');
        });
      }
    } catch (e) {
      log('Failed to dispatch receiver command: $e', error: e);
    }
  }
}
