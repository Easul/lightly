import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/video/infrastructure/video_proxy_server.dart';

void main() {
  test('forwards requests through the injected proxy resolver', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxyServer = VideoProxyServer();
    Uri? resolvedProxyUri;
    addTearDown(() async {
      await proxyServer.stop();
      await upstream.close(force: true);
    });

    upstream.listen((request) async {
      request.response
        ..headers.contentType = ContentType.text
        ..write('video-data');
      await request.response.close();
    });

    await proxyServer.start(
      proxyResolver: (uri) {
        resolvedProxyUri = uri;
        return 'DIRECT';
      },
    );
    final target = Uri(
      scheme: 'http',
      host: upstream.address.host,
      port: upstream.port,
      path: '/stream',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final request = await client.getUrl(
      Uri.parse(proxyServer.buildProxyUrl(target.toString())),
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();

    expect(response.statusCode, HttpStatus.ok);
    expect(body, 'video-data');
    expect(resolvedProxyUri, target);
  });
}
