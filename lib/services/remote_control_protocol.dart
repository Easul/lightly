import 'dart:convert';

/// 远程控制消息类型
enum ControlMessageType { gesture, keyboard, heartbeat, status, error, ack }

/// 手势动作类型
enum GestureAction { tap, swipe, longPress, pinch }

/// 全局操作类型
enum GlobalAction { back, home, recents }

/// 控制消息基类
abstract class ControlMessage {
  final ControlMessageType type;
  final int id;
  final int timestamp;

  ControlMessage({
    required this.type,
    required this.id,
    required this.timestamp,
  });

  Map<String, dynamic> toJson();

  factory ControlMessage.fromJson(Map<String, dynamic> json) {
    final type = ControlMessageType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => ControlMessageType.error,
    );

    switch (type) {
      case ControlMessageType.gesture:
        return GestureCommand.fromJson(json);
      case ControlMessageType.keyboard:
        return KeyboardCommand.fromJson(json);
      case ControlMessageType.heartbeat:
        return HeartbeatMessage.fromJson(json);
      case ControlMessageType.status:
        return StatusMessage.fromJson(json);
      case ControlMessageType.ack:
        return AckMessage.fromJson(json);
      case ControlMessageType.error:
        return ErrorMessage.fromJson(json);
    }
  }
}

class GestureCommand extends ControlMessage {
  final GestureAction action;
  final double? x;
  final double? y;
  final double? startX;
  final double? startY;
  final double? endX;
  final double? endY;
  final double? centerX;
  final double? centerY;
  final double? scale;
  final int duration;

  GestureCommand({
    required this.action,
    required super.id,
    required super.timestamp,
    this.x,
    this.y,
    this.startX,
    this.startY,
    this.endX,
    this.endY,
    this.centerX,
    this.centerY,
    this.scale,
    this.duration = 100,
  }) : super(type: ControlMessageType.gesture);

  factory GestureCommand.tap({
    required double x,
    required double y,
    int duration = 60,
  }) {
    return GestureCommand(
      action: GestureAction.tap,
      id: DateTime.now().millisecondsSinceEpoch,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      x: x,
      y: y,
      duration: duration,
    );
  }

  factory GestureCommand.swipe({
    required double startX,
    required double startY,
    required double endX,
    required double endY,
    int duration = 300,
  }) {
    return GestureCommand(
      action: GestureAction.swipe,
      id: DateTime.now().millisecondsSinceEpoch,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      startX: startX,
      startY: startY,
      endX: endX,
      endY: endY,
      duration: duration,
    );
  }

  factory GestureCommand.longPress({
    required double x,
    required double y,
    int duration = 800,
  }) {
    return GestureCommand(
      action: GestureAction.longPress,
      id: DateTime.now().millisecondsSinceEpoch,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      x: x,
      y: y,
      duration: duration,
    );
  }

  factory GestureCommand.pinch({
    required double centerX,
    required double centerY,
    required double scale,
    int duration = 200,
  }) {
    return GestureCommand(
      action: GestureAction.pinch,
      id: DateTime.now().millisecondsSinceEpoch,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      centerX: centerX,
      centerY: centerY,
      scale: scale,
      duration: duration,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};

    switch (action) {
      case GestureAction.tap:
        data['x'] = x;
        data['y'] = y;
        data['duration'] = duration;
        break;
      case GestureAction.swipe:
        data['startX'] = startX;
        data['startY'] = startY;
        data['endX'] = endX;
        data['endY'] = endY;
        data['duration'] = duration;
        break;
      case GestureAction.longPress:
        data['x'] = x;
        data['y'] = y;
        data['duration'] = duration;
        break;
      case GestureAction.pinch:
        data['centerX'] = centerX;
        data['centerY'] = centerY;
        data['scale'] = scale;
        data['duration'] = duration;
        break;
    }

    return {
      'type': 'gesture',
      'action': action.name,
      'id': id,
      'ts': timestamp,
      'data': data,
    };
  }

  factory GestureCommand.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final action = GestureAction.values.firstWhere(
      (e) => e.name == json['action'],
      orElse: () => GestureAction.tap,
    );

    return GestureCommand(
      action: action,
      id: json['id'] as int? ?? 0,
      timestamp: json['ts'] as int? ?? 0,
      x: (data['x'] as num?)?.toDouble(),
      y: (data['y'] as num?)?.toDouble(),
      startX: (data['startX'] as num?)?.toDouble(),
      startY: (data['startY'] as num?)?.toDouble(),
      endX: (data['endX'] as num?)?.toDouble(),
      endY: (data['endY'] as num?)?.toDouble(),
      centerX: (data['centerX'] as num?)?.toDouble(),
      centerY: (data['centerY'] as num?)?.toDouble(),
      scale: (data['scale'] as num?)?.toDouble(),
      duration: data['duration'] as int? ?? 100,
    );
  }
}

class KeyboardCommand extends ControlMessage {
  final String? text;
  final int? keyCode;

  KeyboardCommand({
    required super.id,
    required super.timestamp,
    this.text,
    this.keyCode,
  }) : super(type: ControlMessageType.keyboard);

  factory KeyboardCommand.text({required String text}) {
    return KeyboardCommand(
      id: DateTime.now().millisecondsSinceEpoch,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      text: text,
    );
  }

  factory KeyboardCommand.key({required int keyCode}) {
    return KeyboardCommand(
      id: DateTime.now().millisecondsSinceEpoch,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      keyCode: keyCode,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'keyboard',
      'action': text != null ? 'text' : 'key',
      'id': id,
      'ts': timestamp,
      'data': {'text': text, 'keyCode': keyCode},
    };
  }

  factory KeyboardCommand.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    return KeyboardCommand(
      id: json['id'] as int? ?? 0,
      timestamp: json['ts'] as int? ?? 0,
      text: data['text'] as String?,
      keyCode: data['keyCode'] as int?,
    );
  }
}

class HeartbeatMessage extends ControlMessage {
  HeartbeatMessage({required super.id, required super.timestamp})
    : super(type: ControlMessageType.heartbeat);

  factory HeartbeatMessage.now() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return HeartbeatMessage(id: now, timestamp: now);
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'heartbeat', 'id': id, 'ts': timestamp};
  }

  factory HeartbeatMessage.fromJson(Map<String, dynamic> json) {
    return HeartbeatMessage(
      id: json['id'] as int? ?? 0,
      timestamp: json['ts'] as int? ?? 0,
    );
  }
}

class StatusMessage extends ControlMessage {
  final String action;
  final Map<String, dynamic> data;

  StatusMessage({
    required this.action,
    required this.data,
    required super.id,
    required super.timestamp,
  }) : super(type: ControlMessageType.status);

  factory StatusMessage.screenInfo({
    required int width,
    required int height,
    required double density,
    int? captureWidth,
    int? captureHeight,
  }) {
    final data = <String, dynamic>{
      'width': width,
      'height': height,
      'density': density,
    };
    if (captureWidth != null && captureHeight != null) {
      data['captureWidth'] = captureWidth;
      data['captureHeight'] = captureHeight;
    }
    return StatusMessage(
      action: 'screen_info',
      data: data,
      id: DateTime.now().millisecondsSinceEpoch,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory StatusMessage.portConfig({
    required int controlPort,
    required int screenPort,
  }) {
    return StatusMessage(
      action: 'port_config',
      data: {'controlPort': controlPort, 'screenPort': screenPort},
      id: DateTime.now().millisecondsSinceEpoch,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory StatusMessage.requestKeyFrame() {
    return StatusMessage(
      action: 'request_key_frame',
      data: const {},
      id: DateTime.now().millisecondsSinceEpoch,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory StatusMessage.updateBitrate({required int bitrate}) {
    return StatusMessage(
      action: 'update_bitrate',
      data: {'bitrate': bitrate},
      id: DateTime.now().millisecondsSinceEpoch,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory StatusMessage.receiverMicrophone({required bool enabled}) {
    return StatusMessage(
      action: 'receiver_microphone',
      data: {'enabled': enabled},
      id: DateTime.now().millisecondsSinceEpoch,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory StatusMessage.receiverMicrophoneStatus({required bool enabled}) {
    return StatusMessage(
      action: 'receiver_microphone_status',
      data: {'enabled': enabled},
      id: DateTime.now().millisecondsSinceEpoch,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory StatusMessage.overlayText({required String text}) {
    return StatusMessage(
      action: 'overlay_text',
      data: {'text': text},
      id: DateTime.now().millisecondsSinceEpoch,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'status',
      'action': action,
      'id': id,
      'ts': timestamp,
      'data': data,
    };
  }

  factory StatusMessage.fromJson(Map<String, dynamic> json) {
    return StatusMessage(
      action: json['action'] as String? ?? '',
      data: json['data'] as Map<String, dynamic>? ?? {},
      id: json['id'] as int? ?? 0,
      timestamp: json['ts'] as int? ?? 0,
    );
  }
}

class AckMessage extends ControlMessage {
  final bool success;
  final String? error;

  AckMessage({
    required this.success,
    this.error,
    required super.id,
    required super.timestamp,
  }) : super(type: ControlMessageType.ack);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'ack',
      'id': id,
      'ts': timestamp,
      'success': success,
      'error': error,
    };
  }

  factory AckMessage.fromJson(Map<String, dynamic> json) {
    return AckMessage(
      success: json['success'] as bool? ?? false,
      error: json['error'] as String?,
      id: json['id'] as int? ?? 0,
      timestamp: json['ts'] as int? ?? 0,
    );
  }
}

class ErrorMessage extends ControlMessage {
  final String message;

  ErrorMessage({
    required this.message,
    required super.id,
    required super.timestamp,
  }) : super(type: ControlMessageType.error);

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'error', 'id': id, 'ts': timestamp, 'message': message};
  }

  factory ErrorMessage.fromJson(Map<String, dynamic> json) {
    return ErrorMessage(
      message: json['message'] as String? ?? 'Unknown error',
      id: json['id'] as int? ?? 0,
      timestamp: json['ts'] as int? ?? 0,
    );
  }
}

class RemoteControlCodec {
  static String encode(ControlMessage message) {
    return jsonEncode(message.toJson());
  }

  static ControlMessage? decode(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return ControlMessage.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  static List<ControlMessage> decodeMultiple(String data) {
    final messages = <ControlMessage>[];
    final lines = data.split('\n');

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final message = decode(line);
      if (message != null) {
        messages.add(message);
      }
    }

    return messages;
  }
}
