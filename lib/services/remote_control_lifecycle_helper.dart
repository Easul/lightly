import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/remote_control_config.dart';

class RemoteControlControllerConnectionResult {
  final Socket controlSocket;
  final Socket? screenSocket;

  const RemoteControlControllerConnectionResult({
    required this.controlSocket,
    required this.screenSocket,
  });
}

class RemoteControlLifecycleHelper {
  const RemoteControlLifecycleHelper();

  Future<RemoteControlControllerConnectionResult> connectControllerSockets({
    required String host,
    required RemoteControlConfig config,
    bool useProxy = false,
    int? proxyPort,
    required void Function(Uint8List) onControlData,
    required void Function(dynamic error) onControlError,
    required void Function() onControlDone,
    required void Function(Uint8List) onScreenDataRaw,
    required void Function(dynamic error, Socket socket) onScreenError,
    required void Function(Socket socket) onScreenDone,
  }) async {
    final controlConnection = await _connectSocket(
      host: host,
      port: config.ports.controlPort,
      useProxy: useProxy,
      proxyPort: proxyPort,
    );
    final controlSocket = controlConnection.socket;
    controlSocket.setOption(SocketOption.tcpNoDelay, true);
    controlConnection.stream.listen(
      onControlData,
      onError: onControlError,
      onDone: onControlDone,
    );

    Socket? screenSocket;
    if (config.enableScreen) {
      final screenConnection = await _connectSocket(
        host: host,
        port: config.ports.screenPort,
        useProxy: useProxy,
        proxyPort: proxyPort,
      );
      screenSocket = screenConnection.socket;
      screenSocket.setOption(SocketOption.tcpNoDelay, true);
      screenConnection.stream.listen(
        onScreenDataRaw,
        onError: (error) => onScreenError(error, screenSocket!),
        onDone: () => onScreenDone(screenSocket!),
      );
    }

    return RemoteControlControllerConnectionResult(
      controlSocket: controlSocket,
      screenSocket: screenSocket,
    );
  }

  Future<Socket> connectControllerScreenSocket({
    required String host,
    required RemoteControlConfig config,
    bool useProxy = false,
    int? proxyPort,
    required void Function(Uint8List) onScreenDataRaw,
    required void Function(dynamic error, Socket socket) onScreenError,
    required void Function(Socket socket) onScreenDone,
  }) async {
    final screenConnection = await _connectSocket(
      host: host,
      port: config.ports.screenPort,
      useProxy: useProxy,
      proxyPort: proxyPort,
    );
    final screenSocket = screenConnection.socket;
    screenSocket.setOption(SocketOption.tcpNoDelay, true);
    screenConnection.stream.listen(
      onScreenDataRaw,
      onError: (error) => onScreenError(error, screenSocket),
      onDone: () => onScreenDone(screenSocket),
    );
    return screenSocket;
  }

  Future<_ConnectedSocket> _connectSocket({
    required String host,
    required int port,
    bool useProxy = false,
    int? proxyPort,
  }) async {
    if (!useProxy || proxyPort == null) {
      final socket = await Socket.connect(
        InternetAddress.tryParse(host) ?? host,
        port,
        timeout: const Duration(milliseconds: 1500),
      );
      return _ConnectedSocket(socket: socket, stream: socket);
    }

    // 使用 SOCKS5 代理连接
    final proxySocket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      proxyPort,
      timeout: const Duration(milliseconds: 3000),
    );
    final incomingStream = proxySocket.asBroadcastStream();

    // 创建缓冲区读取器
    final reader = _ProxySocketReader(incomingStream);

    // 发送 SOCKS5 认证协商请求
    proxySocket.add(const [0x05, 0x01, 0x00]);
    await proxySocket.flush();

    // 接收认证响应
    final authResponse = await reader.readBytes(2);
    if (authResponse.length < 2 ||
        authResponse[0] != 0x05 ||
        authResponse[1] != 0x00) {
      await reader.dispose();
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
    final responseHeader = await reader.readBytes(4);
    if (responseHeader.length < 4 ||
        responseHeader[0] != 0x05 ||
        responseHeader[1] != 0x00) {
      await reader.dispose();
      throw Exception('代理连接请求失败');
    }

    // 读取绑定地址
    final addrType = responseHeader[3];
    if (addrType == 0x01) {
      await reader.readBytes(6);
    } else if (addrType == 0x03) {
      final domainLen = await reader.readByte();
      await reader.readBytes(domainLen + 2);
    } else if (addrType == 0x04) {
      await reader.readBytes(18);
    }

    final buffered = reader.takeBuffered();
    await reader.dispose();
    return _ConnectedSocket(
      socket: proxySocket,
      stream: _prependBufferedData(incomingStream, buffered),
    );
  }

  Stream<Uint8List> _prependBufferedData(
    Stream<Uint8List> source,
    List<int> buffered,
  ) {
    if (buffered.isEmpty) {
      return source;
    }
    late StreamController<Uint8List> controller;
    StreamSubscription<Uint8List>? subscription;

    controller = StreamController<Uint8List>(
      onListen: () {
        controller.add(Uint8List.fromList(buffered));
        subscription = source.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  void attachReceiverControlClient({
    required Socket client,
    required void Function(Uint8List data) onData,
    required void Function(dynamic error) onError,
    required void Function() onDone,
  }) {
    client.listen(onData, onError: onError, onDone: onDone);
  }

  void attachReceiverScreenClient({
    required Socket client,
    required void Function(Uint8List data) onData,
    required void Function(dynamic error, Socket socket) onError,
    required void Function(Socket socket) onDone,
  }) {
    client.listen(
      onData,
      onError: (error) => onError(error, client),
      onDone: () => onDone(client),
    );
  }
}

class _ConnectedSocket {
  final Socket socket;
  final Stream<Uint8List> stream;

  const _ConnectedSocket({required this.socket, required this.stream});
}

/// SOCKS5 代理连接的缓冲区读取器
class _ProxySocketReader {
  final List<int> _buffer = [];
  StreamSubscription<List<int>>? _subscription;
  final _completers = <_ReadRequest>[];

  _ProxySocketReader(Stream<List<int>> stream) {
    _subscription = stream.listen(_onData, onDone: _onDone, onError: _onError);
  }

  void _onData(List<int> data) {
    _buffer.addAll(data);
    _checkPendingReads();
  }

  void _onDone() {
    for (final request in _completers) {
      if (!request.completer.isCompleted) {
        request.completer.complete(List<int>.from(_buffer));
      }
    }
    _completers.clear();
  }

  void _onError(Object error) {
    for (final request in _completers) {
      if (!request.completer.isCompleted) {
        request.completer.completeError(error);
      }
    }
    _completers.clear();
  }

  void _checkPendingReads() {
    while (_completers.isNotEmpty) {
      final request = _completers.first;
      if (_buffer.length >= request.length) {
        _completers.removeAt(0);
        final result = _buffer.sublist(0, request.length);
        _buffer.removeRange(0, request.length);
        if (!request.completer.isCompleted) {
          request.completer.complete(result);
        }
      } else {
        break;
      }
    }
  }

  Future<List<int>> readBytes(int length) async {
    if (_buffer.length >= length) {
      final result = _buffer.sublist(0, length);
      _buffer.removeRange(0, length);
      return result;
    }

    final completer = Completer<List<int>>();
    _completers.add(_ReadRequest(length, completer));

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException('读取超时'),
    );
  }

  Future<int> readByte() async {
    final bytes = await readBytes(1);
    return bytes.isNotEmpty ? bytes[0] : 0;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
  }

  List<int> takeBuffered() {
    final buffered = List<int>.from(_buffer);
    _buffer.clear();
    return buffered;
  }
}

class _ReadRequest {
  final int length;
  final Completer<List<int>> completer;

  _ReadRequest(this.length, this.completer);
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}
