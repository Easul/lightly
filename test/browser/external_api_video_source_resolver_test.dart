import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/video/infrastructure/external_api_video_source_resolver.dart';

void main() {
  group('ExternalApiVideoSourceResolver', () {
    for (final apiPath in ['', '/parse', '/parse/']) {
      test('accepts parser API path "$apiPath"', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        Uri? proxyRequestUri;
        addTearDown(server.close);
        server.listen((request) async {
          expect(request.method, 'POST');
          expect(request.uri.path, '/parse');
          expect(jsonDecode(await utf8.decoder.bind(request).join()), {
            'url': 'https://www.youtube.com/watch?v=bPMCvFYxcxk',
          });
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
          apiBaseUrl: 'http://${server.address.host}:${server.port}$apiPath',
          proxyResolver: (uri) {
            proxyRequestUri = uri;
            return 'DIRECT';
          },
        );

        final resolved = await resolver.resolve(
          'https://www.youtube.com/watch?v=bPMCvFYxcxk',
        );

        expect(resolved.videoId, 'bPMCvFYxcxk');
        expect(resolved.title, 'Example video title');
        expect(resolved.streamUrl, 'https://cdn.example.com/videoplayback');
        expect(proxyRequestUri?.path, '/parse');
      });
    }
  });
}
