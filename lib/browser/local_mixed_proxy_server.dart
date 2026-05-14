import 'dart:async';
import 'dart:io';

import 'http_proxy_protocol_handler.dart';
import 'proxy_buffered_stream_reader.dart';
import 'proxy_http_header_reader.dart';
import 'socks5_protocol_handler.dart';
import 'vless_client.dart';

const bool _proxyVerboseLogging = false;

void _proxyLog(String message) {
  if (_proxyVerboseLogging) {
    print(message);
  }
}

/// 本地 mixed 代理服务器
/// 同时提供 HTTP 与 SOCKS5 入口。
class LocalMixedProxyServer {
  LocalMixedProxyServer({HttpProxyProtocolHandler? httpProxyProtocolHandler})
    : _httpProxyProtocolHandler =
          httpProxyProtocolHandler ?? const HttpProxyProtocolHandler(),
      _socks5ProtocolHandler = const Socks5ProtocolHandler(
        localHost: localHost,
      );

  static const String localHost = '127.0.0.1';

  static String normalizeHttpProxyRequestLineForOrigin(String requestLine) {
    return HttpProxyProtocolHandler.normalizeHttpProxyRequestLineForOrigin(
      requestLine,
    );
  }

  ServerSocket? _serverSocket;
  bool _isRunning = false;
  VlessConfig? _activeConfig;
  final List<VlessTunnel> _activeTunnels = [];
  final HttpProxyProtocolHandler _httpProxyProtocolHandler;
  final Socks5ProtocolHandler _socks5ProtocolHandler;

  bool get isRunning => _isRunning;
  int? get boundPort => _serverSocket?.port;

  Future<void> start(VlessConfig config, {int? preferredPort}) async {
    await stop();

    _activeConfig = config;
    try {
      _serverSocket = await ServerSocket.bind(
        localHost,
        preferredPort ?? 0,
        shared: true,
      );
    } on SocketException catch (e) {
      throw SocketException(
        'Failed to create server socket: ${e.message}. '
        'Unable to create a local mixed proxy listener.',
      );
    }
    _isRunning = true;

    _serverSocket!.listen(
      (clientSocket) {
        unawaited(_handleClient(clientSocket));
      },
      onError: (_) {},
      onDone: () {
        _isRunning = false;
      },
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    _isRunning = false;

    final serverSocket = _serverSocket;
    _serverSocket = null;
    if (serverSocket != null) {
      try {
        await serverSocket.close();
      } catch (_) {}
    }

    final tunnels = List<VlessTunnel>.from(_activeTunnels);
    _activeTunnels.clear();
    for (final tunnel in tunnels) {
      await tunnel.close();
    }
  }

  Future<void> _handleClient(Socket clientSocket) async {
    final config = _activeConfig;
    if (config == null) {
      _proxyLog('LocalMixedProxy: no active config');
      clientSocket.destroy();
      return;
    }

    try {
      // 使用带缓存的 reader 直接包装 socket
      final reader = BufferedStreamReader(clientSocket);
      reader.start();

      // 读取第一个字节来判断协议类型
      final firstByte = await reader.readByte();

      _proxyLog(
        'LocalMixedProxy: detected first byte 0x${firstByte.toRadixString(16)}',
      );

      if (_isHttpProtocolByte(firstByte)) {
        _proxyLog('LocalMixedProxy: handling as HTTP proxy');
        reader.pushBack(firstByte);
        await _httpProxyProtocolHandler.handleHttpProtocol(
          clientSocket: clientSocket,
          reader: reader,
          config: config,
          activeTunnels: _activeTunnels,
          log: _proxyLog,
        );
      } else if (firstByte == 0x05) {
        _proxyLog('LocalMixedProxy: handling as SOCKS5 proxy');
        reader.pushBack(firstByte);
        await _socks5ProtocolHandler.handleSocks5Protocol(
          clientSocket: clientSocket,
          reader: reader,
          config: config,
          activeTunnels: _activeTunnels,
          boundPort: boundPort,
          log: _proxyLog,
        );
      } else {
        _proxyLog(
          'LocalMixedProxy: rejecting unsupported protocol byte: 0x${firstByte.toRadixString(16)}',
        );
        await reader.close();
        clientSocket.destroy();
      }
    } catch (e, st) {
      if (e is Exception &&
          e.toString().contains(
            'Unexpected end of stream while reading byte',
          )) {
        clientSocket.destroy();
        return;
      }
      _proxyLog('LocalMixedProxy: error handling client: $e');
      _proxyLog('LocalMixedProxy: $st');
      clientSocket.destroy();
    }
  }

  bool _isHttpProtocolByte(int byte) {
    // HTTP 方法的首字母
    return byte == 0x47 || // 'G' (GET)
        byte == 0x50 || // 'P' (POST, PUT, PATCH)
        byte == 0x48 || // 'H' (HEAD)
        byte == 0x44 || // 'D' (DELETE)
        byte == 0x4F || // 'O' (OPTIONS)
        byte == 0x54 || // 'T' (TRACE)
        byte == 0x43; // 'C' (CONNECT)
  }
}
