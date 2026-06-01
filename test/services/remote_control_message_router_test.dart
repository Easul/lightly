import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/services/remote_control_message_router.dart';
import 'package:lightly/services/remote_control_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RemoteControlMessageRouter', () {
    test('buffers partial controller messages until newline arrives', () {
      final router = RemoteControlMessageRouter();
      final first = utf8.encode('{"type":"status","action":"screen');
      final second = utf8.encode(
        '_info","id":1,"ts":2,"data":{"width":1,"height":2}}\n',
      );

      expect(
        router.decodeControllerMessages(Uint8List.fromList(first)),
        isEmpty,
      );

      final messages = router.decodeControllerMessages(
        Uint8List.fromList(second),
      );

      expect(messages, hasLength(1));
      expect(messages.single, isA<StatusMessage>());
      expect((messages.single as StatusMessage).action, 'screen_info');
    });

    test('decodes packed controller messages', () {
      final router = RemoteControlMessageRouter();
      final heartbeat = RemoteControlCodec.encode(HeartbeatMessage.now());
      final status = RemoteControlCodec.encode(
        StatusMessage.receiverMicrophoneStatus(enabled: true),
      );

      final messages = router.decodeControllerMessages(
        Uint8List.fromList(utf8.encode('$heartbeat\n$status\n')),
      );

      expect(messages, hasLength(2));
      expect(messages.first, isA<HeartbeatMessage>());
      expect(messages.last, isA<StatusMessage>());
    });

    test('resetController clears partial controller payload', () {
      final router = RemoteControlMessageRouter();
      router.decodeControllerMessages(
        Uint8List.fromList(utf8.encode('{"type":"heartbeat"')),
      );

      router.resetController();

      final messages = router.decodeControllerMessages(
        Uint8List.fromList(utf8.encode(',"id":1,"ts":2}\n')),
      );
      expect(messages, isEmpty);
    });

    test('dispatches receiver heartbeat and sends ack', () async {
      final router = RemoteControlMessageRouter();
      final emitted = <ControlMessage>[];
      final acks = <int>[];
      final receivedHeartbeats = <HeartbeatMessage>[];
      final heartbeat = HeartbeatMessage(id: 7, timestamp: 8);

      router.dispatchReceiverData(
        Uint8List.fromList(
          utf8.encode('${RemoteControlCodec.encode(heartbeat)}\n'),
        ),
        channel: const MethodChannel('remote_control_test'),
        minBitrate: 1,
        maxBitrate: 10,
        recordStatusMessage: (_) {},
        emitMessage: emitted.add,
        requestKeyFrame: () async {},
        updateBitrate: (_) async {},
        sendAck: (messageId, success, [error]) async {
          if (success) {
            acks.add(messageId);
          }
        },
        onHeartbeat: receivedHeartbeats.add,
        log: (_, {error}) {},
      );

      expect(emitted.single, isA<HeartbeatMessage>());
      expect(receivedHeartbeats.single.id, 7);
      expect(acks, <int>[7]);
    });

    test('dispatches receiver status actions to callbacks', () {
      final router = RemoteControlMessageRouter();
      var keyFrameRequests = 0;
      final bitrateUpdates = <int>[];

      router.dispatchReceiverData(
        Uint8List.fromList(
          utf8.encode(
            '${RemoteControlCodec.encode(StatusMessage.requestKeyFrame())}\n'
            '${RemoteControlCodec.encode(StatusMessage.updateBitrate(bitrate: 999999))}\n',
          ),
        ),
        channel: const MethodChannel('remote_control_test'),
        minBitrate: 100,
        maxBitrate: 1000,
        recordStatusMessage: (_) {},
        emitMessage: (_) {},
        requestKeyFrame: () async {
          keyFrameRequests++;
        },
        updateBitrate: (bitrate) async {
          bitrateUpdates.add(bitrate);
        },
        sendAck: (messageId, success, [error]) async {},
        onHeartbeat: (_) {},
        log: (_, {error}) {},
      );

      expect(keyFrameRequests, 1);
      expect(bitrateUpdates, <int>[1000]);
    });

    test('forwards generic receiver status messages', () {
      final router = RemoteControlMessageRouter();
      final recorded = <ControlMessage>[];
      final emitted = <ControlMessage>[];
      final status = StatusMessage.screenInfo(width: 1, height: 2, density: 3);

      router.dispatchReceiverData(
        Uint8List.fromList(
          utf8.encode('${RemoteControlCodec.encode(status)}\n'),
        ),
        channel: const MethodChannel('remote_control_test'),
        minBitrate: 1,
        maxBitrate: 10,
        recordStatusMessage: recorded.add,
        emitMessage: emitted.add,
        requestKeyFrame: () async {},
        updateBitrate: (_) async {},
        sendAck: (messageId, success, [error]) async {},
        onHeartbeat: (_) {},
        log: (_, {error}) {},
      );

      expect(recorded.single, isA<StatusMessage>());
      expect(emitted.single, isA<StatusMessage>());
    });
  });
}
