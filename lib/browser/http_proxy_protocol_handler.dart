import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'proxy_buffered_stream_reader.dart';
import 'proxy_http_header_reader.dart';
import 'vless_client.dart';

typedef ProxyLogCallback = void Function(String message);

class HttpProxyProtocolHandler {
  const HttpProxyProtocolHandler();

  static String normalizeHttpProxyRequestLineForOrigin(String requestLine) {
    final parts = requestLine.split(' ');
    if (parts.length < 3) {
      return requestLine;
    }

    final method = parts[0];
    final target = parts[1];
    final version = parts[2];
    final uri = Uri.tryParse(target);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return requestLine;
    }

    final normalizedPath = _originFormTarget(uri);
    return '$method $normalizedPath $version';
  }

  static String _originFormTarget(Uri uri) {
    final buffer = StringBuffer(uri.path.isEmpty ? '/' : uri.path);
    if (uri.hasQuery) {
      buffer.write('?${uri.query}');
    }
    return buffer.toString();
  }

  Future<void> handleHttpProtocol({
    required Socket clientSocket,
    required BufferedStreamReader reader,
    required VlessConfig config,
    required List<VlessTunnel> activeTunnels,
    required ProxyLogCallback log,
  }) async {
    VlessTunnel? tunnel;

    try {
      final headerReader = HttpHeaderReader(reader);
      final requestLine = await headerReader.readLine();
      if (requestLine == null || requestLine.isEmpty) {
        throw Exception('Empty HTTP request line');
      }

      log('LocalMixedProxy: HTTP requestLine=$requestLine');

      final parts = requestLine.split(' ');
      if (parts.length < 2) {
        throw Exception('Invalid HTTP request line');
      }

      final method = parts[0].toUpperCase();
      final path = parts[1];

      String targetHost;
      int targetPort;

      if (method == 'CONNECT') {
        final authority = parseConnectAuthority(path);
        if (authority == null) {
          throw Exception('Invalid CONNECT path');
        }
        targetHost = authority.$1;
        targetPort = authority.$2;

        await headerReader.readHeaders();
        final remaining = headerReader.takeRemaining();
        await headerReader.close();

        log('LocalMixedProxy: HTTP CONNECT $targetHost:$targetPort');

        tunnel = VlessTunnel(config);
        activeTunnels.add(tunnel);
        await tunnel.connect(targetHost, targetPort);

        clientSocket.add(
          ascii.encode('HTTP/1.1 200 Connection established\r\n\r\n'),
        );
        await clientSocket.flush();

        log('LocalMixedProxy: HTTP tunnel connected');
        log('LocalMixedProxy: starting pipeBroadcast');
        tunnel.pipeBroadcast(reader.stream, clientSocket);

        log('LocalMixedProxy: HTTP remaining=${remaining.length}');
        if (remaining.isNotEmpty) {
          log(
            'LocalMixedProxy: forwarding ${remaining.length} buffered bytes to tunnel',
          );
          tunnel.writeToTarget(remaining);
        }

        clientSocket.done.whenComplete(() async {
          activeTunnels.remove(tunnel);
          await tunnel!.close();
        });
        return;
      }

      final headers = await headerReader.readHeaders();
      final remaining = headerReader.takeRemaining();
      await headerReader.close();

      final hostHeader = headers['host'] ?? '';
      if (hostHeader.isEmpty) {
        throw Exception('Missing Host header');
      }

      final hostParts = hostHeader.split(':');
      targetHost = hostParts[0];
      targetPort = hostParts.length > 1 ? int.tryParse(hostParts[1]) ?? 80 : 80;

      log('LocalMixedProxy: HTTP $method $targetHost:$targetPort');

      tunnel = VlessTunnel(config);
      activeTunnels.add(tunnel);
      await tunnel.connect(targetHost, targetPort);

      log('LocalMixedProxy: starting pipeBroadcast');
      tunnel.pipeBroadcast(reader.stream, clientSocket);

      final forwardedRequestLine = normalizeHttpProxyRequestLineForOrigin(
        requestLine,
      );
      tunnel.writeToTarget(ascii.encode('$forwardedRequestLine\r\n'));
      for (final entry in headers.entries) {
        tunnel.writeToTarget(ascii.encode('${entry.key}: ${entry.value}\r\n'));
      }
      tunnel.writeToTarget(ascii.encode('\r\n'));
      if (remaining.isNotEmpty) {
        log(
          'LocalMixedProxy: forwarding ${remaining.length} buffered bytes to tunnel',
        );
        tunnel.writeToTarget(remaining);
      }

      clientSocket.done.whenComplete(() async {
        activeTunnels.remove(tunnel);
        await tunnel!.close();
      });
    } catch (e, st) {
      log('LocalMixedProxy: HTTP error: $e');
      log('LocalMixedProxy: $st');
      await reader.close();
      await tunnel?.close();
      sendHttpError(clientSocket, '502 Bad Gateway');
    }
  }

  void sendHttpError(Socket clientSocket, String status) {
    try {
      clientSocket.add(
        ascii.encode('HTTP/1.1 $status\r\nContent-Length: 0\r\n\r\n'),
      );
      clientSocket.flush().then((_) => clientSocket.destroy());
    } catch (_) {
      clientSocket.destroy();
    }
  }

  (String, int)? parseConnectAuthority(String authority) {
    final trimmed = authority.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    if (trimmed.startsWith('[')) {
      final closingBracket = trimmed.indexOf(']');
      if (closingBracket <= 1 ||
          closingBracket >= trimmed.length - 2 ||
          trimmed[closingBracket + 1] != ':') {
        return null;
      }
      final host = trimmed.substring(1, closingBracket);
      final port = int.tryParse(trimmed.substring(closingBracket + 2)) ?? 443;
      return (host, port);
    }

    final separatorIndex = trimmed.lastIndexOf(':');
    if (separatorIndex <= 0 || separatorIndex >= trimmed.length - 1) {
      return null;
    }
    final host = trimmed.substring(0, separatorIndex);
    final port = int.tryParse(trimmed.substring(separatorIndex + 1)) ?? 443;
    return (host, port);
  }
}
