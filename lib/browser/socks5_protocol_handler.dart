import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'proxy_buffered_stream_reader.dart';
import 'vless_client.dart';

typedef Socks5LogCallback = void Function(String message);

class Socks5ProtocolHandler {
  const Socks5ProtocolHandler({required this.localHost});

  final String localHost;

  Future<void> handleSocks5Protocol({
    required Socket clientSocket,
    required BufferedStreamReader reader,
    required VlessConfig config,
    required List<VlessTunnel> activeTunnels,
    required int? boundPort,
    required Socks5LogCallback log,
  }) async {
    VlessTunnel? tunnel;

    try {
      final version = await reader.readByte();
      if (version != 0x05) {
        throw Exception('Invalid SOCKS version');
      }

      final methodCount = await reader.readByte();
      if (methodCount <= 0) {
        throw Exception('Missing SOCKS auth methods');
      }
      final methods = await reader.readBytes(methodCount);
      final authMethod = selectSocks5AuthMethod(methods);
      if (authMethod == null) {
        clientSocket.add(const [0x05, 0xff]);
        await clientSocket.flush();
        clientSocket.destroy();
        return;
      }

      clientSocket.add([0x05, authMethod]);
      await clientSocket.flush();
      if (authMethod == 0x02) {
        await consumeSocks5UserPassAuth(reader, clientSocket);
      }

      final requestVersion = await reader.readByte();
      final command = await reader.readByte();
      await reader.readByte();
      final addressType = await reader.readByte();

      if (requestVersion != 0x05) {
        throw Exception('Invalid SOCKS request version');
      }
      if (command != 0x01) {
        await sendSocks5Reply(clientSocket, 0x07);
        return;
      }

      final targetHost = await readSocks5TargetHost(reader, addressType);
      final portBytes = await reader.readBytes(2);
      final targetPort = (portBytes[0] << 8) | portBytes[1];

      tunnel = VlessTunnel(config);
      activeTunnels.add(tunnel);
      await tunnel.connect(targetHost, targetPort);

      await sendSocks5Reply(
        clientSocket,
        0x00,
        bindAddress: tunnel.localBindAddress ?? InternetAddress(localHost),
        bindPort: tunnel.localBindPort ?? boundPort ?? 0,
      );

      tunnel.pipeBroadcast(reader.stream, clientSocket);
      final remaining = reader.takeBuffered();
      if (remaining.isNotEmpty) {
        tunnel.writeToTarget(remaining);
      }

      clientSocket.done.whenComplete(() async {
        activeTunnels.remove(tunnel);
        await tunnel!.close();
      });
    } catch (e, st) {
      log('LocalMixedProxy: SOCKS5 error: $e');
      log('LocalMixedProxy: $st');
      await reader.close();
      await tunnel?.close();
      try {
        await sendSocks5Reply(clientSocket, 0x01);
      } catch (_) {
        clientSocket.destroy();
      }
    }
  }

  Future<void> sendSocks5Reply(
    Socket clientSocket,
    int replyCode, {
    InternetAddress? bindAddress,
    int bindPort = 0,
  }) async {
    final address = bindAddress ?? InternetAddress(localHost);
    final addressBytes = address.rawAddress;
    final addressType = address.type == InternetAddressType.IPv6 ? 0x04 : 0x01;

    clientSocket.add([0x05, replyCode, 0x00, addressType, ...addressBytes]);
    clientSocket.add([(bindPort >> 8) & 0xff, bindPort & 0xff]);
    await clientSocket.flush();
    if (replyCode != 0x00) {
      clientSocket.destroy();
    }
  }

  int? selectSocks5AuthMethod(Uint8List methods) {
    if (methods.contains(0x00)) {
      return 0x00;
    }
    if (methods.contains(0x02)) {
      return 0x02;
    }
    return null;
  }

  Future<void> consumeSocks5UserPassAuth(
    BufferedStreamReader reader,
    Socket clientSocket,
  ) async {
    final version = await reader.readByte();
    if (version != 0x01) {
      throw Exception('Invalid SOCKS auth version');
    }

    final usernameLength = await reader.readByte();
    await reader.readBytes(usernameLength);
    final passwordLength = await reader.readByte();
    await reader.readBytes(passwordLength);

    clientSocket.add(const [0x01, 0x00]);
    await clientSocket.flush();
  }

  Future<String> readSocks5TargetHost(
    BufferedStreamReader reader,
    int addressType,
  ) async {
    switch (addressType) {
      case 0x01:
        final addressBytes = await reader.readBytes(4);
        return addressBytes.join('.');
      case 0x03:
        final length = await reader.readByte();
        final addressBytes = await reader.readBytes(length);
        return utf8.decode(addressBytes);
      case 0x04:
        final addressBytes = await reader.readBytes(16);
        final parts = <String>[];
        for (var index = 0; index < 16; index += 2) {
          final value = (addressBytes[index] << 8) | addressBytes[index + 1];
          parts.add(value.toRadixString(16));
        }
        return parts.join(':');
      default:
        throw Exception('Unsupported SOCKS address type: $addressType');
    }
  }
}
