import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_config.dart';

class AiMessage {
  const AiMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, String> toJson() => <String, String>{
    'role': role,
    'content': content,
  };
}

class AiClient {
  AiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<String>> fetchModels(AiConfig config) async {
    final response = await _client.get(
      _buildUri(config.baseUrl, 'models'),
      headers: _headers(config),
    );
    _ensureSuccess(response.statusCode, response.body);
    final decoded = jsonDecode(response.body);
    final root = decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    final rawModels = root?['data'] ?? root?['models'];
    if (rawModels is! List) return const <String>[];
    final models =
        rawModels
            .map((item) {
              if (item is String) return item;
              if (item is Map) {
                return item['id']?.toString() ?? item['name']?.toString() ?? '';
              }
              return '';
            })
            .where((item) => item.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return models;
  }

  Future<String> translate({
    required AiConfig config,
    required String text,
    required String targetLanguage,
  }) async {
    final normalizedTarget = switch (targetLanguage) {
      '中文' => 'Simplified Chinese',
      '英文' => 'English',
      '日文' => 'Japanese',
      '韩文' => 'Korean',
      _ => targetLanguage,
    };
    final instruction = targetLanguage == '自动'
        ? 'Detect whether the input is primarily Chinese or English. '
              'Translate Chinese to English and English to Simplified Chinese.'
        : 'Translate the input into $normalizedTarget.';
    final messages = <AiMessage>[
      const AiMessage(
        role: 'system',
        content:
            'You are a translation tool. Return only the translated text, '
            'without explanation, quotation marks, or notes.',
      ),
      AiMessage(role: 'user', content: '$instruction\n\n$text'),
    ];
    final response = await _client.post(
      _buildUri(config.baseUrl, config.endpoint.path),
      headers: _headers(config),
      body: jsonEncode(_requestBody(config, messages, stream: false)),
    );
    _ensureSuccess(response.statusCode, response.body);
    return _extractCompletedText(config.endpoint, jsonDecode(response.body));
  }

  Stream<String> streamChat({
    required AiConfig config,
    required List<AiMessage> messages,
  }) async* {
    final request =
        http.Request('POST', _buildUri(config.baseUrl, config.endpoint.path))
          ..headers.addAll(_headers(config))
          ..body = jsonEncode(_requestBody(config, messages, stream: true));
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      _ensureSuccess(response.statusCode, body);
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final pending = StringBuffer();
    final yieldStopwatch = Stopwatch()..start();
    var emittedFirstChunk = false;
    await for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith(':')) continue;
      final payload = line.startsWith('data:')
          ? line.substring(5).trim()
          : line;
      if (payload == '[DONE]') break;
      dynamic decoded;
      try {
        decoded = jsonDecode(payload);
      } on FormatException {
        if (!line.startsWith('event:')) pending.write(payload);
        continue;
      }
      var delta = _extractStreamDelta(config.endpoint, decoded);
      if (delta.isEmpty && !emittedFirstChunk) {
        try {
          final completedPayload = decoded is Map && decoded['response'] is Map
              ? decoded['response']
              : decoded;
          delta = _extractCompletedText(config.endpoint, completedPayload);
        } on FormatException {
          continue;
        }
      }
      if (delta.isEmpty) continue;
      if (!emittedFirstChunk) {
        emittedFirstChunk = true;
        yield delta;
        yieldStopwatch.reset();
        continue;
      }
      pending.write(delta);
      if (pending.length >= 24 || yieldStopwatch.elapsedMilliseconds >= 32) {
        final chunk = pending.toString();
        pending.clear();
        yield chunk;
        yieldStopwatch.reset();
      }
    }
    if (pending.isNotEmpty) yield pending.toString();
  }

  Map<String, dynamic> _requestBody(
    AiConfig config,
    List<AiMessage> messages, {
    required bool stream,
  }) {
    switch (config.endpoint) {
      case AiEndpointType.openAiCompletions:
        return <String, dynamic>{
          'model': config.model,
          'prompt': _completionPrompt(messages),
          'stream': stream,
          'max_tokens': 2048,
        };
      case AiEndpointType.openAiResponses:
        return <String, dynamic>{
          'model': config.model,
          'input': messages.map((message) => message.toJson()).toList(),
          'stream': stream,
        };
      case AiEndpointType.anthropicMessages:
        final system = messages
            .where((message) => message.role == 'system')
            .map((message) => message.content)
            .join('\n');
        return <String, dynamic>{
          'model': config.model,
          if (system.isNotEmpty) 'system': system,
          'messages': messages
              .where((message) => message.role != 'system')
              .map((message) => message.toJson())
              .toList(),
          'stream': stream,
          'max_tokens': 2048,
        };
    }
  }

  String _completionPrompt(List<AiMessage> messages) {
    final buffer = StringBuffer();
    for (final message in messages) {
      final label = switch (message.role) {
        'assistant' => 'Assistant',
        'system' => 'System',
        _ => 'User',
      };
      buffer.writeln('$label: ${message.content}');
    }
    buffer.write('Assistant:');
    return buffer.toString();
  }

  Map<String, String> _headers(AiConfig config) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final key = config.apiKey.trim();
    if (key.isNotEmpty) {
      headers['Authorization'] = 'Bearer $key';
      if (config.endpoint == AiEndpointType.anthropicMessages) {
        headers['x-api-key'] = key;
        headers['anthropic-version'] = '2023-06-01';
      }
    }
    return headers;
  }

  Uri _buildUri(String baseUrl, String resource) {
    var normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (normalized.isEmpty) throw const FormatException('请先填写 Base URL');
    if (normalized.endsWith('/v1/$resource')) return Uri.parse(normalized);
    if (normalized.endsWith('/v1')) {
      return Uri.parse('$normalized/$resource');
    }
    return Uri.parse('$normalized/v1/$resource');
  }

  String _extractCompletedText(AiEndpointType endpoint, dynamic decoded) {
    if (decoded is! Map) throw const FormatException('接口返回格式不正确');
    final root = Map<String, dynamic>.from(decoded);
    switch (endpoint) {
      case AiEndpointType.openAiCompletions:
        final choices = root['choices'];
        if (choices is List && choices.isNotEmpty && choices.first is Map) {
          final choice = Map<String, dynamic>.from(choices.first as Map);
          return (choice['text'] ??
                  (choice['message'] is Map
                      ? (choice['message'] as Map)['content']
                      : null) ??
                  '')
              .toString()
              .trim();
        }
      case AiEndpointType.openAiResponses:
        final direct = root['output_text'];
        if (direct is String && direct.isNotEmpty) return direct.trim();
        final output = root['output'];
        if (output is List) {
          final parts = <String>[];
          for (final item in output.whereType<Map>()) {
            final content = item['content'];
            if (content is List) {
              for (final part in content.whereType<Map>()) {
                final text = part['text'];
                if (text is String) parts.add(text);
              }
            }
          }
          if (parts.isNotEmpty) return parts.join().trim();
        }
      case AiEndpointType.anthropicMessages:
        final content = root['content'];
        if (content is List) {
          return content
              .whereType<Map>()
              .map((part) => part['text']?.toString() ?? '')
              .join()
              .trim();
        }
    }
    throw const FormatException('接口未返回文本内容');
  }

  String _extractStreamDelta(AiEndpointType endpoint, dynamic decoded) {
    if (decoded is! Map) return '';
    final root = Map<String, dynamic>.from(decoded);
    final error = root['error'];
    if (error != null) throw StateError(error.toString());
    switch (endpoint) {
      case AiEndpointType.openAiCompletions:
        final choices = root['choices'];
        if (choices is List && choices.isNotEmpty && choices.first is Map) {
          final choice = Map<String, dynamic>.from(choices.first as Map);
          final delta = choice['delta'];
          if (delta is Map) {
            return _withReasoning(
              reasoning:
                  delta['reasoning_content']?.toString() ??
                  delta['reasoning']?.toString() ??
                  '',
              text: delta['content']?.toString() ?? '',
            );
          }
          return choice['text']?.toString() ?? '';
        }
      case AiEndpointType.openAiResponses:
        if (root['type'] == 'response.output_text.delta') {
          return root['delta']?.toString() ?? '';
        }
        if (root['type'] == 'response.reasoning_text.delta' ||
            root['type'] == 'response.reasoning_summary_text.delta') {
          return _withReasoning(reasoning: root['delta']?.toString() ?? '');
        }
        return root['delta'] is String ? root['delta'] as String : '';
      case AiEndpointType.anthropicMessages:
        final delta = root['delta'];
        if (delta is Map) {
          return _withReasoning(
            reasoning: delta['thinking']?.toString() ?? '',
            text: delta['text']?.toString() ?? '',
          );
        }
    }
    return '';
  }

  String _withReasoning({String reasoning = '', String text = ''}) {
    if (reasoning.isEmpty) return text;
    return '<think>$reasoning</think>$text';
  }

  void _ensureSuccess(int statusCode, String body) {
    if (statusCode >= 200 && statusCode < 300) return;
    var message = body.trim();
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          message = error['message']?.toString() ?? error.toString();
        } else if (error != null) {
          message = error.toString();
        }
      }
    } catch (_) {}
    throw StateError('请求失败（$statusCode）：$message');
  }

  void close() => _client.close();
}
