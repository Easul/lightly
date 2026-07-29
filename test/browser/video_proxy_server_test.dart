import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/video/infrastructure/video_proxy_server.dart';

void main() {
  test(
    'forwards allowlisted requests with server-side session headers',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final proxyServer = VideoProxyServer(
        allowedHostSuffixes: const <String>['127.0.0.1'],
      );
      Uri? resolvedProxyUri;
      String? receivedCookie;
      String? receivedReferer;
      String? receivedUnknownHeader;
      addTearDown(() async {
        await proxyServer.stop();
        await upstream.close(force: true);
      });

      upstream.listen((request) async {
        receivedCookie = request.headers.value(HttpHeaders.cookieHeader);
        receivedReferer = request.headers.value(HttpHeaders.refererHeader);
        receivedUnknownHeader = request.headers.value('x-private-header');
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
      final proxyUrl = proxyServer.buildProxyUrl(
        target.toString(),
        headers: const <String, String>{
          HttpHeaders.cookieHeader: 'SID=secret',
          HttpHeaders.refererHeader: 'https://m.youtube.com/',
          'x-private-header': 'must-not-forward',
        },
      );
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final request = await client.getUrl(Uri.parse(proxyUrl));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();

      expect(response.statusCode, HttpStatus.ok);
      expect(body, 'video-data');
      expect(resolvedProxyUri, target);
      expect(receivedCookie, 'SID=secret');
      expect(receivedReferer, 'https://m.youtube.com/');
      expect(receivedUnknownHeader, isNull);
      expect(proxyUrl, isNot(contains('secret')));
      expect(proxyUrl, isNot(contains('SID')));
    },
  );

  test('does not accept sensitive headers from the local client', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxyServer = VideoProxyServer(
      allowedHostSuffixes: const <String>['127.0.0.1'],
    );
    String? receivedCookie;
    addTearDown(() async {
      await proxyServer.stop();
      await upstream.close(force: true);
    });

    upstream.listen((request) async {
      receivedCookie = request.headers.value(HttpHeaders.cookieHeader);
      request.response
        ..contentLength = 1
        ..add(<int>[1]);
      await request.response.close();
    });
    await proxyServer.start(proxyResolver: (_) => 'DIRECT');

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
    request.headers.set(HttpHeaders.cookieHeader, 'attacker=value');
    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.ok);
    expect(receivedCookie, isNull);
  });

  test('rejects hosts that only share an allowlist suffix', () async {
    final proxyServer = VideoProxyServer();
    addTearDown(proxyServer.stop);
    await proxyServer.start(proxyResolver: (_) => 'DIRECT');
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final proxyUri = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: proxyServer.boundPort!,
      path: '/proxy',
      queryParameters: const <String, String>{
        'url': 'https://notgooglevideo.com/stream',
      },
    );
    final response = await (await client.getUrl(proxyUri)).close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.forbidden);
  });

  test('binds a header context token to its exact target URL', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxyServer = VideoProxyServer(
      allowedHostSuffixes: const <String>['127.0.0.1'],
    );
    var upstreamHits = 0;
    addTearDown(() async {
      await proxyServer.stop();
      await upstream.close(force: true);
    });
    upstream.listen((request) async {
      upstreamHits++;
      await request.response.close();
    });
    await proxyServer.start(proxyResolver: (_) => 'DIRECT');

    final originalTarget =
        'http://${upstream.address.host}:${upstream.port}/original';
    final proxyUri = Uri.parse(
      proxyServer.buildProxyUrl(
        originalTarget,
        headers: const <String, String>{HttpHeaders.cookieHeader: 'SID=secret'},
      ),
    );
    final tamperedUri = proxyUri.replace(
      queryParameters: <String, String>{
        ...proxyUri.queryParameters,
        'url': 'http://${upstream.address.host}:${upstream.port}/tampered',
      },
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(tamperedUri)).close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.forbidden);
    expect(upstreamHits, 0);
  });

  test('relays redirects without following them upstream', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxyServer = VideoProxyServer(
      allowedHostSuffixes: const <String>['127.0.0.1'],
    );
    var upstreamHits = 0;
    addTearDown(() async {
      await proxyServer.stop();
      await upstream.close(force: true);
    });
    upstream.listen((request) async {
      upstreamHits++;
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(
          HttpHeaders.locationHeader,
          'https://untrusted.example/stream',
        );
      await request.response.close();
    });
    await proxyServer.start(proxyResolver: (_) => 'DIRECT');

    final target = 'http://${upstream.address.host}:${upstream.port}/redirect';
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(
      Uri.parse(
        proxyServer.buildProxyUrl(
          target,
          headers: const <String, String>{
            HttpHeaders.cookieHeader: 'SID=secret',
          },
        ),
      ),
    );
    request.followRedirects = false;
    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.found);
    expect(
      response.headers.value(HttpHeaders.locationHeader),
      'https://untrusted.example/stream',
    );
    expect(upstreamHits, 1);
  });
}
