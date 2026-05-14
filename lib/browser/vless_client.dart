import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

export 'vless_protocol_helpers.dart';
import 'vless_protocol_helpers.dart';

const bool _vlessVerboseLogging = false;

void _vlessLog(String message) {
  if (_vlessVerboseLogging) {
    print(message);
  }
}

class VlessConfig {
  VlessConfig({
    required this.uuid,
    required this.host,
    required this.port,
    this.sni,
    this.transportType,
    this.wsPath,
    this.wsHost,
    this.security,
    this.packetEncoding,
    this.tlsInsecure = false,
    this.name,
  });

  final String uuid;
  final String host;
  final int port;
  final String? sni;
  final String? transportType;
  final String? wsPath;
  final String? wsHost;
  final String? security;
  final String? packetEncoding;
  final bool tlsInsecure;
  final String? name;

  String get webSocketPath => wsPath?.trim().isNotEmpty == true ? wsPath! : '/';

  String get webSocketTlsServerName {
    // CRITICAL: TLS SNI and WS Host are not interchangeable here.
    // Real-world nodes depend on keeping the TLS name resolution separate
    // from the HTTP Host header fallback chain.
    final normalizedSni = sni?.trim();
    if (normalizedSni != null && normalizedSni.isNotEmpty) {
      return normalizedSni;
    }

    final normalizedWsHost = wsHost?.trim();
    if (normalizedWsHost != null && normalizedWsHost.isNotEmpty) {
      return normalizedWsHost;
    }

    return host;
  }

  String get webSocketHttpHost {
    // CRITICAL: HTTP Host must stay independent from the TLS/SNI decision.
    // Some ws-tls nodes succeed only when the HTTP Host follows wsHost while
    // the TLS handshake still uses the TLS server name above.
    final normalizedWsHost = wsHost?.trim();
    if (normalizedWsHost != null && normalizedWsHost.isNotEmpty) {
      return normalizedWsHost;
    }

    return webSocketTlsServerName;
  }

  bool get isTlsEnabled {
    final sec = (security ?? '').trim().toLowerCase();
    if (sec == 'tls' || sec == 'reality' || sec == 'xtls') {
      return true;
    }
    // 默认：443 端口视为 TLS，其他端口根据显式 security 判断
    if (sec.isNotEmpty) {
      return sec != 'none';
    }
    return port == 443;
  }

  factory VlessConfig.parse(String uriString) {
    final uri = Uri.parse(uriString);
    if (uri.scheme != 'vless') {
      throw FormatException('Unsupported VLESS URI: $uriString');
    }

    final uuid = Uri.decodeComponent(uri.userInfo);
    if (uuid.isEmpty) {
      throw FormatException('VLESS UUID is required');
    }

    final query = uri.queryParameters;
    return VlessConfig(
      uuid: uuid,
      host: uri.host,
      port: uri.port,
      sni: _readOptionalQueryValue(uri, 'sni') ?? uri.host,
      transportType: _readOptionalQueryValue(uri, 'type'),
      wsPath: _readOptionalQueryValue(uri, 'path'),
      wsHost: _readOptionalQueryValue(uri, 'host'),
      security: _readOptionalQueryValue(uri, 'security'),
      packetEncoding: _readOptionalQueryValue(uri, 'packetEncoding'),
      tlsInsecure:
          _readBoolQueryValue(uri, 'allowInsecure') ||
          _readBoolQueryValue(uri, 'insecure'),
      name: uri.fragment.isEmpty ? null : Uri.decodeComponent(uri.fragment),
    );
  }

  static String? _readOptionalQueryValue(Uri uri, String key) {
    final value = uri.queryParameters[key]?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static bool _readBoolQueryValue(Uri uri, String key) {
    final value = uri.queryParameters[key]?.trim().toLowerCase();
    return value == '1' || value == 'true' || value == 'yes';
  }
}

class VlessTunnel {
  VlessTunnel(this.config);

  static Future<void> _webSocketRetrySequence = Future<void>.value();
  static DateTime? _lastWebSocketRetryAt;

  final VlessConfig config;

  SecureSocket? _socket;
  _WebSocketTransport? _webSocket;
  HttpClient? _httpClient;
  StreamSubscription<List<int>>? _socketToClientSubscription;
  StreamSubscription<List<int>>? _clientToSocketSubscription;
  StreamSubscription<dynamic>? _webSocketToClientSubscription;
  StreamSubscription<List<int>>? _clientToWebSocketSubscription;
  bool _isClosed = false;
  bool _responseHeaderPending = true;
  final BytesBuilder _responseHeaderBuffer = BytesBuilder(copy: false);
  Uint8List? _pendingVlessRequest;
  bool _vlessRequestSent = false;
  Timer? _pendingWebSocketRequestTimer;
  InternetAddress? _localBindAddress;
  int? _localBindPort;

  InternetAddress? get localBindAddress => _localBindAddress;
  int? get localBindPort => _localBindPort;

  Future<void> connect(String targetHost, int targetPort) async {
    final connectStart = DateTime.now();
    final request = buildVlessRequest(config.uuid, targetHost, targetPort);
    _vlessLog(
      'VlessTunnel: request hex=${request.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
    );

    if (config.transportType == 'ws') {
      final path = config.webSocketPath;
      final wsHost = config.webSocketHttpHost;
      final tlsServerName = config.webSocketTlsServerName;
      final useTls = config.isTlsEnabled;
      final wsScheme = useTls ? 'wss' : 'ws';

      final resolvedAddresses = await InternetAddress.lookup(config.host);
      if (resolvedAddresses.isEmpty) {
        throw SocketException('Failed to resolve ${config.host}');
      }
      _vlessLog(
        'VlessTunnel: resolved ${config.host} -> '
        '${resolvedAddresses.map((e) => '${e.address}/${e.type.name}').join(', ')}',
      );
      final candidateAddresses = orderPreferredAddresses(resolvedAddresses);
      final targetAddress = candidateAddresses.first;
      _vlessLog(
        'VlessTunnel: selected address '
        '${targetAddress.address}/${targetAddress.type.name}',
      );

      try {
        final wsUrl = '$wsScheme://$tlsServerName:${config.port}$path';
        _vlessLog(
          'VlessTunnel: connecting WebSocket $wsUrl '
          '(TCP=${config.host}, TLS-SNI=$tlsServerName, HTTP-Host=$wsHost, '
          'TLS=$useTls, ip=$targetAddress)',
        );
        _webSocket = await _connectWebSocketWithRetry(
          candidateAddresses: candidateAddresses,
          httpHost: wsHost,
          tlsServerName: tlsServerName,
          path: path,
          useTls: useTls,
        );
        _vlessLog(
          'VlessTunnel: WebSocket connected '
          'in ${DateTime.now().difference(connectStart).inMilliseconds}ms',
        );
      } catch (e, st) {
        _vlessLog('VlessTunnel: WebSocket connect failed: $e');
        _vlessLog('VlessTunnel: stack=$st');
        rethrow;
      }

      // Defer sending VLESS request until pipe/pipeBroadcast is called,
      // ensuring the response handler is ready before any data arrives.
      _pendingVlessRequest = request;
      _vlessLog(
        'VlessTunnel: WebSocket connected, VLESS request deferred, len=${request.length}',
      );
      return;
    }

    // TLS direct (non-WS)
    try {
      _vlessLog(
        'VlessTunnel: connecting TLS ${config.host}:${config.port} '
        '(SNI=${config.sni})',
      );
      final resolvedAddresses = await InternetAddress.lookup(config.host);
      if (resolvedAddresses.isEmpty) {
        throw SocketException('Failed to resolve ${config.host}');
      }
      _vlessLog(
        'VlessTunnel: resolved ${config.host} -> '
        '${resolvedAddresses.map((e) => '${e.address}/${e.type.name}').join(', ')}',
      );
      final candidateAddresses = orderPreferredAddresses(resolvedAddresses);
      final targetAddress = candidateAddresses.first;
      _vlessLog(
        'VlessTunnel: selected address '
        '${targetAddress.address}/${targetAddress.type.name}',
      );
      final socket = await connectSocketWithFallback(
        candidateAddresses,
        config.port,
      );
      _localBindAddress = socket.address;
      _localBindPort = socket.port;
      _socket = await SecureSocket.secure(
        socket,
        host: config.sni,
        context: SecurityContext(withTrustedRoots: true),
        onBadCertificate: config.tlsInsecure ? (_) => true : null,
      );
      _vlessLog(
        'VlessTunnel: TLS connected '
        'in ${DateTime.now().difference(connectStart).inMilliseconds}ms',
      );
    } catch (e, st) {
      print('VlessTunnel: TLS connect failed: $e');
      print('VlessTunnel: stack=$st');
      rethrow;
    }
    // Defer sending VLESS request until pipe/pipeBroadcast is called,
    // ensuring the response handler is ready before any data arrives.
    _pendingVlessRequest = request;
    _vlessLog(
      'VlessTunnel: TLS connected, VLESS request deferred, len=${request.length}',
    );
  }

  Future<_WebSocketTransport> _connectWebSocketWithRetry({
    required List<InternetAddress> candidateAddresses,
    required String httpHost,
    required String tlsServerName,
    required String path,
    required bool useTls,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        final delay = _retryDelayForWebSocketError(lastError, attempt);
        if (delay != null) {
          await Future<void>.delayed(delay);
        }
        await _awaitRetryWebSocketConnectTurn();
      }

      try {
        return await _connectWebSocketManually(
          candidateAddresses: candidateAddresses,
          httpHost: httpHost,
          tlsServerName: tlsServerName,
          path: path,
          useTls: useTls,
        );
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (!_isRetryableWebSocketError(error) || attempt == 3) {
          Error.throwWithStackTrace(error, stackTrace);
        }
      }
    }

    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  Future<void> _awaitRetryWebSocketConnectTurn() async {
    // CRITICAL: only retry attempts are serialized and gap-limited.
    // Do not move this pacing to initial connects, or parallel clients such as
    // Telegram can be starved before they establish their first tunnel.
    final previous = _webSocketRetrySequence;
    final completer = Completer<void>();
    _webSocketRetrySequence = completer.future;
    await previous;

    try {
      final lastAt = _lastWebSocketRetryAt;
      if (lastAt != null) {
        final elapsed = DateTime.now().difference(lastAt);
        const minGap = Duration(milliseconds: 400);
        if (elapsed < minGap) {
          await Future<void>.delayed(minGap - elapsed);
        }
      }
      _lastWebSocketRetryAt = DateTime.now();
    } finally {
      completer.complete();
    }
  }

  bool _isRetryableWebSocketError(Object? error) {
    if (error is HttpException) {
      return error.message.contains('429');
    }

    if (error is SocketException) {
      final message = error.message.toLowerCase();
      return message.contains('software caused connection abort') ||
          message.contains('timed out waiting for websocket upgrade') ||
          message.contains('connection timed out') ||
          message.contains('connection reset by peer') ||
          message.contains('connection aborted');
    }

    return false;
  }

  @visibleForTesting
  bool isRetryableWebSocketErrorForTest(Object? error) {
    return _isRetryableWebSocketError(error);
  }

  Duration? _retryDelayForWebSocketError(Object? error, int attempt) {
    if (!_isRetryableWebSocketError(error)) {
      return null;
    }

    switch (attempt) {
      case 1:
        return const Duration(milliseconds: 800);
      case 2:
        return const Duration(milliseconds: 1600);
      case 3:
        return const Duration(milliseconds: 2400);
      default:
        return null;
    }
  }

  void writeToTarget(List<int> data) {
    if (_webSocket != null) {
      _writeWebSocketPayload(data);
      return;
    }
    _socket?.add(data);
  }

  void pipe(Socket clientSocket) {
    if (_webSocket != null) {
      _pipeWebSocket(clientSocket);
      return;
    }

    final socket = _socket;
    if (socket == null) {
      clientSocket.destroy();
      return;
    }

    // CRITICAL: Set up listeners FIRST, before sending any data.
    _socketToClientSubscription = socket.listen(
      (data) {
        final payload = _consumeResponseHeader(data);
        if (payload != null && payload.isNotEmpty) {
          clientSocket.add(payload);
        }
      },
      onError: (_) {
        clientSocket.destroy();
        unawaited(close());
      },
      onDone: () {
        _vlessLog(
          'VlessTunnel: client websocket input completed, keeping upstream open',
        );
      },
      cancelOnError: true,
    );

    _clientToSocketSubscription = clientSocket.listen(
      (data) {
        socket.add(data);
      },
      onError: (_) {
        clientSocket.destroy();
        unawaited(close());
      },
      onDone: () {
        clientSocket.destroy();
        unawaited(close());
      },
      cancelOnError: true,
    );

    // Send VLESS request AFTER listeners are set up.
    _sendVlessRequestIfNeeded(socket);
  }

  void pipeBroadcast(Stream<Uint8List> incoming, IOSink outgoing) {
    if (_webSocket != null) {
      _pipeWebSocketBroadcast(incoming, outgoing);
      return;
    }

    final socket = _socket;
    if (socket == null) {
      outgoing.close();
      return;
    }

    // Track whether outgoing is closed to avoid Broken pipe errors
    var outgoingClosed = false;

    // CRITICAL: Set up listeners FIRST, before sending any data.
    _socketToClientSubscription = socket.listen(
      (data) {
        if (outgoingClosed) {
          return;
        }
        final payload = _consumeResponseHeader(data);
        if (payload != null && payload.isNotEmpty) {
          try {
            outgoing.add(payload);
          } on SocketException {
            outgoingClosed = true;
          }
        }
      },
      onError: (_) {
        if (!outgoingClosed) {
          outgoingClosed = true;
          unawaited(outgoing.close().catchError((_) {}));
        }
        unawaited(close());
      },
      onDone: () {
        if (!outgoingClosed) {
          outgoingClosed = true;
          unawaited(outgoing.close().catchError((_) {}));
        }
        unawaited(close());
      },
      cancelOnError: true,
    );

    _clientToSocketSubscription = incoming.listen(
      (data) {
        if (_isClosed) {
          return;
        }
        try {
          socket.add(data);
        } on SocketException {
          // Socket closed, ignore and let cleanup happen via onDone/onError
        }
      },
      onError: (_) {
        if (!outgoingClosed) {
          outgoingClosed = true;
          unawaited(outgoing.close().catchError((_) {}));
        }
        unawaited(close());
      },
      onDone: () {
        _vlessLog('VlessTunnel: client input completed, keeping upstream open');
      },
      cancelOnError: true,
    );

    // Send VLESS request AFTER listeners are set up.
    _sendVlessRequestIfNeeded(socket);
  }

  void _sendVlessRequestIfNeeded(dynamic target) {
    if (_vlessRequestSent || _pendingVlessRequest == null) {
      return;
    }
    // CRITICAL: this send must happen only after the upstream/client listeners
    // are already registered. Sending earlier can drop the first server reply.
    _vlessRequestSent = true;
    _vlessLog(
      'VlessTunnel: sending VLESS request now, len=${_pendingVlessRequest!.length}',
    );
    if (target is _WebSocketTransport) {
      target.add(_pendingVlessRequest!);
    } else if (target is Socket) {
      target.add(_pendingVlessRequest!);
      unawaited(target.flush().catchError((_) {}));
    }
    _pendingVlessRequest = null;
  }

  void _pipeWebSocket(Socket clientSocket) {
    final webSocket = _webSocket;
    if (webSocket == null) {
      clientSocket.destroy();
      return;
    }

    // CRITICAL: Set up listeners FIRST, before sending any data.
    _webSocketToClientSubscription = webSocket.stream.listen(
      (data) {
        final payload = _consumeResponseHeader(data);
        if (payload != null) {
          try {
            clientSocket.add(payload);
          } on SocketException {
            // Client socket closed, cleanup will happen via onDone/onError
          }
        }
      },
      onError: (_) {
        clientSocket.destroy();
        unawaited(close());
      },
      onDone: () {
        clientSocket.destroy();
        unawaited(close());
      },
      cancelOnError: true,
    );

    _clientToWebSocketSubscription = clientSocket.listen(
      (data) {
        _writeWebSocketPayload(data);
      },
      onError: (_) {
        clientSocket.destroy();
        unawaited(close());
      },
      onDone: () {
        clientSocket.destroy();
        unawaited(close());
      },
      cancelOnError: true,
    );

    _schedulePendingWebSocketRequest(webSocket);
  }

  void _pipeWebSocketBroadcast(Stream<Uint8List> incoming, IOSink outgoing) {
    final webSocket = _webSocket;
    if (webSocket == null) {
      outgoing.close();
      return;
    }

    // CRITICAL: Set up listeners FIRST, before sending any data.
    // This ensures we don't miss any responses from the server.
    _webSocketToClientSubscription = webSocket.stream.listen(
      (data) {
        _vlessLog(
          'VlessTunnel: WS->client raw hex=${data.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}${data.length > 32 ? '...' : ''}',
        );
        final payload = _consumeResponseHeader(data);
        _vlessLog(
          'VlessTunnel: WS->client after header strip: payload=${payload?.length ?? 'null'}',
        );
        if (payload != null) {
          outgoing.add(payload);
        }
      },
      onError: (e, st) {
        _vlessLog('VlessTunnel: WS error: $e');
        _vlessLog('VlessTunnel: WS error stack: $st');
        outgoing.close();
        unawaited(close());
      },
      onDone: () {
        _vlessLog('VlessTunnel: WS done');
        outgoing.close();
        unawaited(close());
      },
      cancelOnError: true,
    );

    _clientToWebSocketSubscription = incoming.listen(
      (data) {
        _writeWebSocketPayload(data);
      },
      onError: (e, st) {
        outgoing.close();
        unawaited(close());
      },
      onDone: () {
        _vlessLog(
          'VlessTunnel: client websocket input completed, keeping upstream open',
        );
      },
      cancelOnError: true,
    );

    _schedulePendingWebSocketRequest(webSocket);
  }

  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;

    await _socketToClientSubscription?.cancel();
    await _clientToSocketSubscription?.cancel();
    await _webSocketToClientSubscription?.cancel();
    await _clientToWebSocketSubscription?.cancel();
    _localBindAddress = null;
    _localBindPort = null;

    try {
      await _socket?.flush();
    } catch (_) {}

    try {
      await _socket?.close();
    } catch (_) {
      _socket?.destroy();
    }

    try {
      _pendingWebSocketRequestTimer?.cancel();
      final closeCode = _webSocket?.closeCode;
      final closeReason = _webSocket?.closeReason;
      if (closeCode != null || closeReason != null) {
        _vlessLog('VlessTunnel: WS close code=$closeCode reason=$closeReason');
      }
      await _webSocket?.close();
    } catch (_) {}

    try {
      _httpClient?.close(force: true);
    } catch (_) {}
    _httpClient = null;
  }

  void _writeWebSocketPayload(List<int> data) {
    final webSocket = _webSocket;
    if (webSocket == null) {
      return;
    }

    final pendingRequest = _pendingVlessRequest;
    if (!_vlessRequestSent && pendingRequest != null) {
      // CRITICAL: combine the deferred VLESS request with the first client
      // payload frame. Some workers-style nodes stall if these are split into
      // separate early frames.
      _pendingWebSocketRequestTimer?.cancel();
      _vlessRequestSent = true;
      _pendingVlessRequest = null;

      final combined = Uint8List(pendingRequest.length + data.length);
      combined.setRange(0, pendingRequest.length, pendingRequest);
      combined.setRange(pendingRequest.length, combined.length, data);
      _vlessLog(
        'VlessTunnel: sending combined VLESS request with payload '
        'request=${pendingRequest.length} payload=${data.length}',
      );
      webSocket.add(combined);
      return;
    }

    webSocket.add(data);
  }

  void _schedulePendingWebSocketRequest(_WebSocketTransport webSocket) {
    if (_vlessRequestSent || _pendingVlessRequest == null) {
      return;
    }

    // CRITICAL: keep this tiny fallback timer. It covers server-speaks-first
    // cases where no client payload arrives to trigger the combined-frame path.
    _pendingWebSocketRequestTimer?.cancel();
    _pendingWebSocketRequestTimer = Timer(const Duration(milliseconds: 8), () {
      if (!_vlessRequestSent) {
        _sendVlessRequestIfNeeded(webSocket);
      }
    });
  }

  Future<_WebSocketTransport> _connectWebSocketManually({
    required List<InternetAddress> candidateAddresses,
    required String httpHost,
    required String tlsServerName,
    required String path,
    required bool useTls,
  }) async {
    final tcpStart = DateTime.now();
    final rawSocket = await connectSocketWithFallback(
      candidateAddresses,
      config.port,
    );
    _localBindAddress = rawSocket.address;
    _localBindPort = rawSocket.port;
    final tcpAddress = rawSocket.remoteAddress;
    _vlessLog(
      'VlessTunnel: TCP connected to ${tcpAddress.address}:${config.port} '
      'in ${DateTime.now().difference(tcpStart).inMilliseconds}ms',
    );
    final tlsStart = DateTime.now();
    final socket = useTls
        ? await SecureSocket.secure(
            rawSocket,
            host: tlsServerName,
            context: SecurityContext(withTrustedRoots: true),
            onBadCertificate: config.tlsInsecure ? (_) => true : null,
          )
        : rawSocket;
    if (useTls) {
      _vlessLog(
        'VlessTunnel: TLS upgraded with SNI=$tlsServerName '
        'in ${DateTime.now().difference(tlsStart).inMilliseconds}ms',
      );
    }

    final webSocketKey = generateWebSocketKey();
    final hostHeader = buildWebSocketHostHeader(
      httpHost: httpHost,
      port: config.port,
      useTls: useTls,
    );
    final requestBuffer = StringBuffer()
      ..write('GET $path HTTP/1.1\r\n')
      ..write('Host: $hostHeader\r\n')
      ..write('Upgrade: websocket\r\n')
      ..write('Connection: Upgrade\r\n')
      ..write('Sec-WebSocket-Key: $webSocketKey\r\n')
      ..write('Sec-WebSocket-Version: 13\r\n')
      ..write('\r\n');

    socket.add(utf8.encode(requestBuffer.toString()));
    await socket.flush();
    _vlessLog('VlessTunnel: sent WS upgrade request path=$path host=$httpHost');

    final responseResult = await _readHttpUpgradeResponse(socket);
    final responseBytes = responseResult.headerBytes;
    final responseText = latin1.decode(responseBytes);
    final headerEnd = responseText.indexOf('\r\n\r\n');
    if (headerEnd == -1) {
      throw const HttpException('Invalid WebSocket upgrade response');
    }

    final headerLines = responseText.substring(0, headerEnd).split('\r\n');
    _vlessLog(
      'VlessTunnel: WS upgrade status '
      '${headerLines.isEmpty ? 'empty' : headerLines.first}',
    );
    if (headerLines.isEmpty || !headerLines.first.contains('101')) {
      unawaited(socket.close());
      throw HttpException(
        'WebSocket upgrade failed: ${headerLines.isEmpty ? 'empty response' : headerLines.first}',
      );
    }

    final headers = <String, String>{};
    for (final line in headerLines.skip(1)) {
      final separatorIndex = line.indexOf(':');
      if (separatorIndex <= 0) {
        continue;
      }
      headers[line.substring(0, separatorIndex).trim().toLowerCase()] = line
          .substring(separatorIndex + 1)
          .trim();
    }
    _vlessLog('VlessTunnel: WS upgrade headers $headers');

    final expectedAccept = base64Encode(
      sha1.convert(utf8.encode('$webSocketKey$webSocketGuid')).bytes,
    );
    if (headers['sec-websocket-accept'] != expectedAccept) {
      throw const HttpException('Invalid WebSocket accept header');
    }

    return _WebSocketTransport(socket, responseResult.remainingStream);
  }

  Future<_HttpUpgradeResult> _readHttpUpgradeResponse(Socket socket) async {
    final bridge = _SocketByteBridge(socket);
    bridge.start();
    return bridge.readHttpHeader().timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        unawaited(bridge.close());
        throw const SocketException('Timed out waiting for WebSocket upgrade');
      },
    );
  }

  bool _containsHttpHeaderTerminator(List<int> bytes) {
    for (var index = 0; index <= bytes.length - 4; index++) {
      if (bytes[index] == 13 &&
          bytes[index + 1] == 10 &&
          bytes[index + 2] == 13 &&
          bytes[index + 3] == 10) {
        return true;
      }
    }
    return false;
  }

  Uint8List? _consumeResponseHeader(List<int> chunk) {
    final result = consumeVlessResponseHeader(
      pending: _responseHeaderPending,
      buffered: _responseHeaderBuffer,
      chunk: chunk,
    );
    _responseHeaderPending = result.headerPending;
    if (!result.headerPending) {
      _vlessLog(
        'VlessTunnel: stripped response header payload=${result.payload?.length ?? 0}',
      );
    }
    return result.payload;
  }
}

class _HttpUpgradeResult {
  const _HttpUpgradeResult({
    required this.headerBytes,
    required this.remainingStream,
  });

  final Uint8List headerBytes;
  final Stream<Uint8List> remainingStream;
}

class _SocketByteBridge {
  _SocketByteBridge(this._stream) {
    _controller = StreamController<Uint8List>(
      onListen: _startForwarding,
      onCancel: _closeController,
    );
  }

  final Stream<List<int>> _stream;
  late final StreamController<Uint8List> _controller;
  StreamSubscription<List<int>>? _subscription;
  final List<int> _buffer = [];
  final List<Completer<void>> _waiters = <Completer<void>>[];
  bool _done = false;
  Object? _error;
  StackTrace? _errorStackTrace;
  bool _forwarding = false;
  bool _closed = false;

  Stream<Uint8List> get stream => _controller.stream;

  void start() {
    _subscription = _stream.listen(
      (data) {
        if (_forwarding) {
          if (_controller.isClosed) {
            return;
          }
          _controller.add(Uint8List.fromList(data));
        } else {
          _buffer.addAll(data);
        }
        _flushWaiters();
      },
      onError: (Object error, StackTrace stackTrace) {
        _error = error;
        _errorStackTrace = stackTrace;
        if (_forwarding && !_controller.isClosed) {
          _controller.addError(error, stackTrace);
          unawaited(_controller.close());
        }
        _flushWaiters();
      },
      onDone: () {
        _done = true;
        if (_forwarding && !_controller.isClosed) {
          unawaited(_controller.close());
        }
        _flushWaiters();
      },
      cancelOnError: true,
    );
  }

  Future<_HttpUpgradeResult> readHttpHeader() async {
    while (true) {
      final headerEnd = indexOfHttpHeaderTerminator(_buffer);
      if (headerEnd != -1) {
        final headerBytes = Uint8List.fromList(_buffer.sublist(0, headerEnd));
        _buffer.removeRange(0, headerEnd);
        return _HttpUpgradeResult(
          headerBytes: headerBytes,
          remainingStream: stream,
        );
      }

      if (_error != null) {
        Error.throwWithStackTrace(
          _error!,
          _errorStackTrace ?? StackTrace.current,
        );
      }
      if (_done) {
        return _HttpUpgradeResult(
          headerBytes: Uint8List.fromList(_buffer),
          remainingStream: stream,
        );
      }

      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
  }

  void _startForwarding() {
    if (_forwarding) {
      return;
    }
    _forwarding = true;

    if (_buffer.isNotEmpty) {
      _controller.add(Uint8List.fromList(_buffer));
      _buffer.clear();
    }

    if (_error != null) {
      _controller.addError(_error!, _errorStackTrace);
      unawaited(_controller.close());
      return;
    }

    if (_done) {
      unawaited(_controller.close());
    }
  }

  void _flushWaiters() {
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeLast();
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _subscription?.cancel();
    await _closeController();
  }

  Future<void> _closeController() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

class _WebSocketTransport {
  _WebSocketTransport(this._socket, Stream<Uint8List> incoming) {
    _incomingSubscription = incoming.listen(
      _onSocketData,
      onError: (Object error, StackTrace stackTrace) {
        if (!_messages.isClosed) {
          _messages.addError(error, stackTrace);
        }
      },
      onDone: () async {
        await _finishIncoming();
      },
      cancelOnError: true,
    );
  }

  final Socket _socket;
  final StreamController<Uint8List> _messages = StreamController<Uint8List>();
  StreamSubscription<Uint8List>? _incomingSubscription;
  final _FrameBuffer _frameBuffer = _FrameBuffer();
  BytesBuilder? _fragmentBuffer;
  int? _fragmentOpcode;
  bool _closed = false;
  bool _closeFrameSent = false;
  int? closeCode;
  String? closeReason;
  Future<void> _writeQueue = Future<void>.value();

  Stream<Uint8List> get stream => _messages.stream;

  void add(List<int> data) {
    if (_closed) {
      return;
    }
    _writeFrame(opcode: 0x02, payload: data);
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    if (!_closeFrameSent) {
      _closeFrameSent = true;
      _writeFrame(opcode: 0x08, payload: const <int>[]);
    }
    try {
      await _writeQueue;
    } catch (_) {}
    await _incomingSubscription?.cancel();
    if (!_messages.isClosed) {
      await _messages.close();
    }
    try {
      await _socket.flush();
    } catch (_) {}
    try {
      await _socket.close();
    } catch (_) {
      _socket.destroy();
    }
  }

  void _onSocketData(Uint8List data) {
    _frameBuffer.addAll(data);
    _drainFrames();
  }

  void _drainFrames() {
    while (true) {
      if (_frameBuffer.length < 2) {
        return;
      }

      final firstByte = _frameBuffer[0];
      final secondByte = _frameBuffer[1];
      final fin = (firstByte & 0x80) != 0;
      final opcode = firstByte & 0x0f;
      final masked = (secondByte & 0x80) != 0;
      var offset = 2;
      var payloadLength = secondByte & 0x7f;

      if (payloadLength == 126) {
        if (_frameBuffer.length < offset + 2) {
          return;
        }
        payloadLength = (_frameBuffer[offset] << 8) | _frameBuffer[offset + 1];
        offset += 2;
      } else if (payloadLength == 127) {
        if (_frameBuffer.length < offset + 8) {
          return;
        }
        var extendedLength = 0;
        for (var index = 0; index < 8; index++) {
          extendedLength = (extendedLength << 8) | _frameBuffer[offset + index];
        }
        payloadLength = extendedLength;
        offset += 8;
      }

      List<int>? maskingKey;
      if (masked) {
        if (_frameBuffer.length < offset + 4) {
          return;
        }
        maskingKey = _frameBuffer.sublist(offset, offset + 4);
        offset += 4;
      }

      final frameEnd = offset + payloadLength;
      if (_frameBuffer.length < frameEnd) {
        return;
      }

      // Avoid removeRange(0, n) which is O(n) - use an offset-based approach
      final payload = Uint8List.fromList(
        _frameBuffer.sublist(offset, frameEnd),
      );
      _frameBuffer.consume(frameEnd);

      if (maskingKey != null) {
        for (var index = 0; index < payload.length; index++) {
          payload[index] ^= maskingKey[index % 4];
        }
      }

      _handleFrame(opcode: opcode, fin: fin, payload: payload);
    }
  }

  void _handleFrame({
    required int opcode,
    required bool fin,
    required Uint8List payload,
  }) {
    switch (opcode) {
      case 0x00:
        if (_fragmentBuffer == null || _fragmentOpcode == null) {
          return;
        }
        _fragmentBuffer!.add(payload);
        if (fin) {
          _emitMessage(_fragmentOpcode!, _fragmentBuffer!.takeBytes());
          _fragmentBuffer = null;
          _fragmentOpcode = null;
        }
        return;
      case 0x01:
      case 0x02:
        if (!fin) {
          _fragmentOpcode = opcode;
          _fragmentBuffer = BytesBuilder(copy: false)..add(payload);
          return;
        }
        _emitMessage(opcode, payload);
        return;
      case 0x08:
        if (payload.length >= 2) {
          closeCode = (payload[0] << 8) | payload[1];
          if (payload.length > 2) {
            closeReason = utf8.decode(payload.sublist(2), allowMalformed: true);
          }
        }
        if (!_closeFrameSent) {
          _closeFrameSent = true;
          _writeFrame(opcode: 0x08, payload: payload);
        }
        unawaited(_finishIncoming());
        return;
      case 0x09:
        _writeFrame(opcode: 0x0a, payload: payload);
        return;
      case 0x0a:
        return;
      default:
        return;
    }
  }

  void _emitMessage(int opcode, List<int> payload) {
    if (_messages.isClosed) {
      return;
    }
    if (opcode == 0x01) {
      _messages.add(
        Uint8List.fromList(
          utf8.encode(utf8.decode(payload, allowMalformed: true)),
        ),
      );
      return;
    }
    _messages.add(Uint8List.fromList(payload));
  }

  Future<void> _finishIncoming() async {
    if (!_messages.isClosed) {
      await _messages.close();
    }
  }

  void _writeFrame({required int opcode, required List<int> payload}) {
    final frame = BytesBuilder(copy: false);
    frame.addByte(0x80 | (opcode & 0x0f));

    final maskingKey = randomBytes(4);
    final payloadLength = payload.length;
    if (payloadLength < 126) {
      frame.addByte(0x80 | payloadLength);
    } else if (payloadLength <= 0xffff) {
      frame.addByte(0x80 | 126);
      frame.add([(payloadLength >> 8) & 0xff, payloadLength & 0xff]);
    } else {
      frame.addByte(0x80 | 127);
      for (var shift = 56; shift >= 0; shift -= 8) {
        frame.addByte((payloadLength >> shift) & 0xff);
      }
    }

    frame.add(maskingKey);
    final maskedPayload = Uint8List.fromList(payload);
    for (var index = 0; index < maskedPayload.length; index++) {
      maskedPayload[index] ^= maskingKey[index % 4];
    }
    frame.add(maskedPayload);

    final frameBytes = frame.takeBytes();
    _writeQueue = _writeQueue.then((_) {
      _socket.add(frameBytes);
    });
  }
}

/// Efficient ring-buffer style frame buffer for WebSocket parsing.
/// Avoids O(n) removeRange operations by maintaining a read offset.
class _FrameBuffer {
  final List<int> _data = [];
  int _readOffset = 0;

  int get length => _data.length - _readOffset;
  bool get isEmpty => length == 0;

  int operator [](int index) => _data[_readOffset + index];

  void addAll(List<int> data) {
    _data.addAll(data);
  }

  /// Returns a view into the buffer without copying.
  /// Note: This returns a view that may become invalid after consume().
  List<int> sublist(int start, int end) {
    final actualStart = _readOffset + start;
    final actualEnd = _readOffset + end;
    if (actualStart < 0 ||
        actualEnd > _data.length ||
        actualStart > actualEnd) {
      throw RangeError('Invalid range: $start-$end (buffer length: ${length})');
    }
    return _data.sublist(actualStart, actualEnd);
  }

  /// Marks bytes as consumed. Compacts the buffer when half is consumed
  /// to avoid unbounded growth of the underlying list.
  void consume(int count) {
    _readOffset += count;
    // Compact when more than half is consumed and buffer is large enough
    if (_readOffset > 1024 && _readOffset > _data.length >> 1) {
      _data.removeRange(0, _readOffset);
      _readOffset = 0;
    }
  }

  /// Clears all data.
  void clear() {
    _data.clear();
    _readOffset = 0;
  }
}
