import 'dart:typed_data';

enum ScreenFrameType { config, keyFrame, deltaFrame }

class ScreenFrame {
  const ScreenFrame({
    required this.type,
    required this.data,
    required this.timestamp,
  });

  final ScreenFrameType type;
  final Uint8List data;
  final int timestamp;
}
