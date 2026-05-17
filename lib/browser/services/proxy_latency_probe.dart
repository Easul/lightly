import 'dart:async';
import 'dart:io';

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
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    if (proxy != null && proxy.isNotEmpty) {
      client.findProxy = (_) => proxy;
    }

    try {
      for (final testUrl in testUrls) {
        final stopwatch = Stopwatch()..start();
        try {
          final request = await client
              .getUrl(Uri.parse(testUrl))
              .timeout(timeout);
          request.followRedirects = true;
          request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
          final response = await request.close().timeout(timeout);
          await response.drain<void>().timeout(timeout);
          stopwatch.stop();
          if (response.statusCode >= 200 && response.statusCode < 500) {
            return stopwatch.elapsed;
          }
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
  }) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      stopwatch.stop();
      return stopwatch.elapsed;
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } finally {
      await socket?.close();
    }
  }
}
