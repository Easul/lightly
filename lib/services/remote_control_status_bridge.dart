import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/remote_control_config.dart';
import 'remote_control_protocol.dart';

class RemoteControlStatusBridge {
  const RemoteControlStatusBridge();

  Future<void> sendScreenInfoStatus({
    required MethodChannel channel,
    required Socket? receiverControlSocket,
  }) async {
    if (receiverControlSocket == null) return;
    final info = await channel.invokeMapMethod<Object?, Object?>(
      'getScreenInfo',
    );
    final width = (info?['width'] as num?)?.toInt();
    final height = (info?['height'] as num?)?.toInt();
    final density = (info?['density'] as num?)?.toDouble();
    final captureWidth = (info?['captureWidth'] as num?)?.toInt();
    final captureHeight = (info?['captureHeight'] as num?)?.toInt();
    if (width == null || height == null || density == null) return;

    final status = StatusMessage.screenInfo(
      width: width,
      height: height,
      density: density,
      captureWidth: captureWidth,
      captureHeight: captureHeight,
    );
    receiverControlSocket.add(
      utf8.encode('${RemoteControlCodec.encode(status)}\n'),
    );
  }

  Future<void> sendPortConfigStatus({
    required Socket? receiverControlSocket,
    required RemoteControlConfig? config,
  }) async {
    if (receiverControlSocket == null || config == null) return;
    final ports = config.ports;
    final status = StatusMessage.portConfig(
      controlPort: ports.controlPort,
      screenPort: ports.screenPort,
    );
    receiverControlSocket.add(
      utf8.encode('${RemoteControlCodec.encode(status)}\n'),
    );
  }

  Future<void> sendHeartbeat({required Socket? controllerControlSocket}) async {
    if (controllerControlSocket == null) return;
    final message = HeartbeatMessage.now();
    controllerControlSocket.add(
      utf8.encode('${RemoteControlCodec.encode(message)}\n'),
    );
  }

  Future<void> sendAck({
    required Socket? receiverControlSocket,
    required int messageId,
    required bool success,
    String? error,
  }) async {
    if (receiverControlSocket == null) return;
    final message = AckMessage(
      success: success,
      error: error,
      id: messageId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    receiverControlSocket.add(
      utf8.encode('${RemoteControlCodec.encode(message)}\n'),
    );
  }

  RemoteControlPortConfig? portConfigFromStatus(StatusMessage message) {
    final controlPort = (message.data['controlPort'] as num?)?.toInt();
    final screenPort = (message.data['screenPort'] as num?)?.toInt();
    if (controlPort == null || screenPort == null) {
      return null;
    }
    return RemoteControlPortConfig(
      controlPort: controlPort,
      screenPort: screenPort,
    );
  }

  void recordStatusMessage({
    required ControlMessage message,
    required void Function(Map<String, dynamic>) onScreenInfo,
    required void Function() markConnectionReady,
    required void Function(RemoteControlPortConfig) onPortConfig,
  }) {
    if (message is! StatusMessage) {
      return;
    }

    if (message.action == 'screen_info') {
      onScreenInfo(Map<String, dynamic>.from(message.data));
      markConnectionReady();
      return;
    }

    if (message.action == 'port_config') {
      final ports = portConfigFromStatus(message);
      if (ports != null) {
        onPortConfig(ports);
      }
    }
  }
}
