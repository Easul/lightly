import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/proxy_service.dart';
import 'package:lightly/browser/services/external_api_video_source_resolver.dart';

void main() {
  group('ExternalApiVideoSourceResolver', () {
    test(
      'extracts title and first playable url from parser response',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        server.listen((request) async {
          expect(request.method, 'POST');
          expect(request.uri.path, '/parse');
          await utf8.decoder.bind(request).join();
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'source_url': 'https://www.youtube.com/watch?v=bPMCvFYxcxk',
              'title': 'Example video title',
              'urls': ['https://cdn.example.com/videoplayback'],
            }),
          );
          await request.response.close();
        });

        final resolver = ExternalApiVideoSourceResolver(
          apiBaseUrl: 'http://${server.address.host}:${server.port}',
          proxyService: ProxyService(),
          settings: BrowserSettings.defaults(),
        );

        final resolved = await resolver.resolve(
          'https://www.youtube.com/watch?v=bPMCvFYxcxk',
        );

        expect(resolved.videoId, 'bPMCvFYxcxk');
        expect(resolved.title, 'Example video title');
        expect(resolved.streamUrl, 'https://cdn.example.com/videoplayback');
      },
    );
  });
}
