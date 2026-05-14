import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../models/remote_control_config.dart';
import 'remote_control_protocol.dart';
import 'remote_control_status_bridge.dart';

class RemoteControlConnectionHelper {
  const RemoteControlConnectionHelper();

  String normalizeRemoteHost(String host) {
    final trimmed = host.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    final slashIndex = trimmed.indexOf('/');
    if (slashIndex <= 0) {
      return trimmed;
    }
    return trimmed.substring(0, slashIndex);
  }

  Future<RemoteControlPortConfig?> discoverReceiverPorts({
    required String host,
    required RemoteControlStatusBridge statusBridge,
    required List<ControlMessage> Function(StringBuffer, Uint8List)
    decodeBufferedMessages,
  }) async {
    final normalizedHost = normalizeRemoteHost(host);
    if (normalizedHost.isEmpty) {
      return null;
    }

    for (final basePort in RemoteControlPortConfig.shuffledBasePorts()) {
      Socket? socket;
      StreamSubscription<Uint8List>? subscription;
      try {
        socket = await Socket.connect(
          normalizedHost,
          basePort,
          timeout: const Duration(milliseconds: 450),
        );
        final completer = Completer<RemoteControlPortConfig?>();
        final buffer = StringBuffer();

        subscription = socket.listen(
          (data) {
            final messages = decodeBufferedMessages(buffer, data);
            for (final message in messages) {
              if (message is StatusMessage && message.action == 'port_config') {
                final ports = statusBridge.portConfigFromStatus(message);
                if (ports != null && !completer.isCompleted) {
                  completer.complete(ports);
                  return;
                }
              }
            }
          },
          onError: (_) {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          },
          onDone: () {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          },
        );

        final ports = await completer.future.timeout(
          const Duration(milliseconds: 500),
          onTimeout: () => null,
        );
        if (ports != null) {
          return ports;
        }
      } catch (_) {
        continue;
      } finally {
        await subscription?.cancel();
        socket?.destroy();
      }
    }

    return null;
  }
}
