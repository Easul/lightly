import 'dart:async';
import 'dart:convert';
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
    bool useProxy = false,
    int? proxyPort,
  }) async {
    final normalizedHost = normalizeRemoteHost(host);
    if (normalizedHost.isEmpty) {
      return null;
    }

    for (final basePort in RemoteControlPortConfig.shuffledBasePorts()) {
      Socket? socket;
      StreamSubscription<Uint8List>? subscription;
      try {
        socket = await _connectSocket(
          host: normalizedHost,
          port: basePort,
          useProxy: useProxy,
          proxyPort: proxyPort,
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

  Future<Socket> _connectSocket({
    required String host,
    required int port,
    bool useProxy = false,
    int? proxyPort,
  }) async {
    if (!useProxy || proxyPort == null) {
      return await Socket.connect(
        InternetAddress.tryParse(host) ?? host,
        port,
        timeout: const Duration(milliseconds: 1500),
      );
    }

    // 使用 SOCKS5 代理连接
    final proxySocket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      proxyPort,
      timeout: const Duration(milliseconds: 3000),
    );

    // 发送 SOCKS5 认证协商请求
    proxySocket.add(const [0x05, 0x01, 0x00]);
    await proxySocket.flush();

    // 接收认证响应
    final authResponse = await _readExact(proxySocket, 2);
    if (authResponse.length < 2 ||
        authResponse[0] != 0x05 ||
        authResponse[1] != 0x00) {
      proxySocket.destroy();
      throw Exception('代理认证失败');
    }

    // 发送连接请求
    final targetAddress = InternetAddress.tryParse(host);
    final List<int> connectRequest = [0x05, 0x01, 0x00];

    if (targetAddress != null &&
        targetAddress.type == InternetAddressType.IPv4) {
      connectRequest.add(0x01);
      connectRequest.addAll(targetAddress.rawAddress);
    } else {
      final domainBytes = utf8.encode(host);
      connectRequest.add(0x03);
      connectRequest.add(domainBytes.length);
      connectRequest.addAll(domainBytes);
    }

    connectRequest.add((port >> 8) & 0xFF);
    connectRequest.add(port & 0xFF);
    proxySocket.add(connectRequest);
    await proxySocket.flush();

    // 接收连接响应
    final responseHeader = await _readExact(proxySocket, 4);
    if (responseHeader.length < 4 ||
        responseHeader[0] != 0x05 ||
        responseHeader[1] != 0x00) {
      proxySocket.destroy();
      throw Exception('代理连接请求失败');
    }

    // 读取绑定地址
    final addrType = responseHeader[3];
    if (addrType == 0x01) {
      await _readExact(proxySocket, 6);
    } else if (addrType == 0x03) {
      final domainLen = await _readByte(proxySocket);
      await _readExact(proxySocket, domainLen + 2);
    } else if (addrType == 0x04) {
      await _readExact(proxySocket, 18);
    }

    return proxySocket;
  }

  Future<List<int>> _readExact(Socket socket, int length) async {
    final result = <int>[];
    final subscription = socket.listen((data) {
      result.addAll(data);
    });

    while (result.length < length) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    await subscription.cancel();
    return result.take(length).toList();
  }

  Future<int> _readByte(Socket socket) async {
    final data = await _readExact(socket, 1);
    return data.isNotEmpty ? data[0] : 0;
  }
}
