import 'dart:async';
import 'dart:io';

class ProxyLatencyTestCanceledException implements Exception {
  const ProxyLatencyTestCanceledException();
}

class ProxyLatencyCancellationToken {
  bool _isCanceled = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isCanceled => _isCanceled;

  void onCancel(void Function() listener) {
    if (_isCanceled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void cancel() {
    if (_isCanceled) {
      return;
    }
    _isCanceled = true;
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void throwIfCanceled() {
    if (_isCanceled) {
      throw const ProxyLatencyTestCanceledException();
    }
  }
}

class ProxyLatencyProbe {
  const ProxyLatencyProbe();

  Future<int?> allocateEphemeralLoopbackPort() async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      return socket.port;
    } finally {
      await socket?.close();
    }
  }

  Future<Duration?> measureHttpRequest({
    required String? proxy,
    required Duration timeout,
    required List<String> testUrls,
    ProxyLatencyCancellationToken? cancellationToken,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    if (proxy != null && proxy.isNotEmpty) {
      client.findProxy = (_) => proxy;
    }
    cancellationToken?.onCancel(() => client.close(force: true));

    try {
      for (final testUrl in testUrls) {
        cancellationToken?.throwIfCanceled();
        final stopwatch = Stopwatch()..start();
        try {
          cancellationToken?.throwIfCanceled();
          final request = await client
              .getUrl(Uri.parse(testUrl))
              .timeout(timeout);
          cancellationToken?.throwIfCanceled();
          request.followRedirects = true;
          request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
          final response = await request.close().timeout(timeout);
          cancellationToken?.throwIfCanceled();
          await response.drain<void>().timeout(timeout);
          stopwatch.stop();
          if (response.statusCode >= 200 && response.statusCode < 500) {
            return stopwatch.elapsed;
          }
        } on ProxyLatencyTestCanceledException {
          rethrow;
        } on TimeoutException {
          continue;
        } on SocketException {
          continue;
        } on HandshakeException {
          continue;
        } on HttpException {
          continue;
        }
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<Duration?> measureTcpConnect({
    required String host,
    required int port,
    required Duration timeout,
    ProxyLatencyCancellationToken? cancellationToken,
  }) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    ConnectionTask<Socket>? connectionTask;
    cancellationToken?.onCancel(() {
      connectionTask?.cancel();
      socket?.destroy();
    });
    try {
      cancellationToken?.throwIfCanceled();
      connectionTask = await Socket.startConnect(host, port);
      socket = await connectionTask.socket.timeout(timeout);
      cancellationToken?.throwIfCanceled();
      stopwatch.stop();
      return stopwatch.elapsed;
    } on ProxyLatencyTestCanceledException {
      rethrow;
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } finally {
      await socket?.close();
    }
  }
}
