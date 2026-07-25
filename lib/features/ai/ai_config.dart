import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum AiEndpointType {
  openAiCompletions,
  openAiResponses,
  anthropicMessages;

  String get label => switch (this) {
    openAiCompletions => 'OpenAI /v1/completions',
    openAiResponses => 'OpenAI /v1/responses',
    anthropicMessages => 'Anthropic /v1/messages',
  };

  String get path => switch (this) {
    openAiCompletions => 'completions',
    openAiResponses => 'responses',
    anthropicMessages => 'messages',
  };
}

class AiConfig {
  const AiConfig({
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.endpoint = AiEndpointType.openAiResponses,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final AiEndpointType endpoint;

  bool get isReady => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  AiConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    AiEndpointType? endpoint,
  }) {
    return AiConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      endpoint: endpoint ?? this.endpoint,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'endpoint': endpoint.name,
  };

  factory AiConfig.fromJson(Map<String, dynamic> json) {
    final endpointName = json['endpoint'] as String?;
    return AiConfig(
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      model: json['model'] as String? ?? '',
      endpoint: AiEndpointType.values.firstWhere(
        (value) => value.name == endpointName,
        orElse: () => AiEndpointType.openAiResponses,
      ),
    );
  }
}

class AiConfigStore {
  static const String _storageKey = 'ai_tools_config';

  Future<AiConfig> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const AiConfig();
    try {
      return AiConfig.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return const AiConfig();
    }
  }

  Future<void> save(AiConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(config.toJson()));
  }
}
