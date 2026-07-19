import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lightly/ai_tools/ai_client.dart';
import 'package:lightly/ai_tools/ai_config.dart';

void main() {
  group('AiClient', () {
    test('queries models from normalized v1 URL', () async {
      late http.Request capturedRequest;
      final client = AiClient(
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'model-b'},
                {'id': 'model-a'},
              ],
            }),
            200,
          );
        }),
      );

      final models = await client.fetchModels(
        const AiConfig(
          baseUrl: 'https://example.com/v1/',
          apiKey: 'secret',
          model: 'model-a',
        ),
      );

      expect(capturedRequest.url.toString(), 'https://example.com/v1/models');
      expect(capturedRequest.headers['Authorization'], 'Bearer secret');
      expect(models, ['model-a', 'model-b']);
    });

    test('builds anthropic translation request', () async {
      late http.Request capturedRequest;
      final client = AiClient(
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': '你好'},
              ],
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final translated = await client.translate(
        config: const AiConfig(
          baseUrl: 'https://example.com',
          apiKey: 'secret',
          model: 'claude-test',
          endpoint: AiEndpointType.anthropicMessages,
        ),
        text: 'hello',
        targetLanguage: '中文',
      );

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(capturedRequest.url.toString(), 'https://example.com/v1/messages');
      expect(capturedRequest.headers['x-api-key'], 'secret');
      expect(body['model'], 'claude-test');
      expect(body['stream'], isFalse);
      expect(translated, '你好');
    });

    test('parses responses API SSE deltas', () async {
      final client = AiClient(
        client: MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              utf8.encode(
                'event: response.output_text.delta\n'
                'data: {"type":"response.output_text.delta","delta":"你"}\n\n',
              ),
              utf8.encode(
                'data: {"type":"response.output_text.delta","delta":"好"}\n\n'
                'data: {"type":"response.completed","response":{"output_text":"你好"}}\n\n'
                'data: [DONE]\n\n',
              ),
            ]),
            200,
          );
        }),
      );

      final chunks = await client
          .streamChat(
            config: const AiConfig(
              baseUrl: 'https://example.com',
              model: 'test-model',
            ),
            messages: const [AiMessage(role: 'user', content: 'hello')],
          )
          .toList();

      expect(chunks.join(), '你好');
      expect(chunks.length, 2);
    });
  });
}
