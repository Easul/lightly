import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/remote_control/application/remote_control_screen_frame_sender.dart';
import 'package:lightly/features/remote_control/domain/screen_frame.dart';

void main() {
  test('sendConfig writes SPS and PPS frames immediately', () {
    final sink = _ControlledSink();
    final sender = RemoteControlScreenFrameSender()..attachSink(sink);

    sender.sendConfig(Uint8List.fromList([1, 2]), Uint8List.fromList([3]));

    expect(sink.writes, hasLength(2));
    _expectFrame(sink.writes[0], type: 0x01, data: [1, 2]);
    _expectFrame(sink.writes[1], type: 0x01, data: [3]);
  });

  test('drops stale pending delta frames while sink is busy', () async {
    final logs = <String>[];
    final sink = _ControlledSink();
    final sender = RemoteControlScreenFrameSender(log: logs.add)
      ..attachSink(sink);

    sender.enqueueFrame(_frame(ScreenFrameType.deltaFrame, [1]));
    await _pumpEventQueue();
    sender.enqueueFrame(_frame(ScreenFrameType.deltaFrame, [2]));
    sender.enqueueFrame(_frame(ScreenFrameType.deltaFrame, [3]));

    expect(sink.writes, hasLength(1));
    _expectFrame(sink.writes[0], type: 0x03, data: [1]);

    sink.completeNextFlush();
    await _pumpEventQueue();

    expect(sink.writes, hasLength(2));
    _expectFrame(sink.writes[1], type: 0x03, data: [3]);
    expect(logs.single, contains('count=1'));
  });

  test('prioritizes key frame and clears stale pending delta', () async {
    final sink = _ControlledSink();
    final sender = RemoteControlScreenFrameSender()..attachSink(sink);

    sender.enqueueFrame(_frame(ScreenFrameType.deltaFrame, [1]));
    await _pumpEventQueue();
    sender.enqueueFrame(_frame(ScreenFrameType.deltaFrame, [2]));
    sender.enqueueFrame(_frame(ScreenFrameType.keyFrame, [9]));

    sink.completeNextFlush();
    await _pumpEventQueue();

    expect(sink.writes, hasLength(2));
    _expectFrame(sink.writes[0], type: 0x03, data: [1]);
    _expectFrame(sink.writes[1], type: 0x02, data: [9]);
    expect(sender.hasPendingFrame, isFalse);
  });

  test('reset drops pending frames after detach', () async {
    final sink = _ControlledSink();
    final sender = RemoteControlScreenFrameSender()..attachSink(sink);

    sender.enqueueFrame(_frame(ScreenFrameType.deltaFrame, [1]));
    await _pumpEventQueue();
    sender.enqueueFrame(_frame(ScreenFrameType.deltaFrame, [2]));
    sender.reset();

    sink.completeNextFlush();
    await _pumpEventQueue();

    expect(sink.writes, hasLength(1));
    _expectFrame(sink.writes[0], type: 0x03, data: [1]);
    expect(sender.hasPendingFrame, isFalse);
  });
}

ScreenFrame _frame(ScreenFrameType type, List<int> data) {
  return ScreenFrame(
    type: type,
    data: Uint8List.fromList(data),
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}

({int type, List<int> data}) _decodeFrame(List<int> bytes) {
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  final length = view.getUint32(1, Endian.big);
  return (type: bytes[0], data: bytes.sublist(5, 5 + length));
}

void _expectFrame(
  List<int> bytes, {
  required int type,
  required List<int> data,
}) {
  final decoded = _decodeFrame(bytes);
  expect(decoded.type, type);
  expect(decoded.data, data);
}

Future<void> _pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _ControlledSink implements IOSink {
  final List<List<int>> writes = <List<int>>[];
  final Queue<Completer<void>> _flushes = Queue<Completer<void>>();
  final Completer<void> _done = Completer<void>();

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {
    writes.add(List<int>.from(data));
  }

  @override
  Future<void> flush() {
    final completer = Completer<void>();
    _flushes.add(completer);
    return completer.future;
  }

  void completeNextFlush() {
    _flushes.removeFirst().complete();
  }

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  void write(Object? object) {}

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? object = '']) {}
}
