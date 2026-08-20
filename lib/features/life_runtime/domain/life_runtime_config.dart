import 'dart:convert';

class MindGitRuntimeConfig {
  const MindGitRuntimeConfig({
    this.host = '127.0.0.1',
    this.port = 8787,
    this.password = '',
    this.workspace = 'default',
  });

  final String host;
  final int port;
  final String password;
  final String workspace;

  MindGitRuntimeConfig copyWith({
    String? host,
    int? port,
    String? password,
    String? workspace,
  }) {
    return MindGitRuntimeConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      password: password ?? this.password,
      workspace: workspace ?? this.workspace,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'host': host,
    'port': port,
    'password': password,
    'workspace': workspace,
  };

  factory MindGitRuntimeConfig.fromJson(Object? value) {
    final json = value is Map ? value : const <String, Object?>{};
    return MindGitRuntimeConfig(
      host: _string(json['host'], '127.0.0.1'),
      port: _int(json['port'], 8787),
      password: _string(json['password'], ''),
      workspace: _string(json['workspace'], 'default'),
    );
  }
}

class LifeRecordAiConfig {
  const LifeRecordAiConfig({
    this.enabled = false,
    this.apiKey = '',
    this.baseUrl = 'https://api.openai.com',
    this.apiType = 'chat_completions',
    this.model = 'gpt-4o-mini',
    this.thinking = true,
    this.tools = true,
    this.systemPrompt = '',
  });

  final bool enabled;
  final String apiKey;
  final String baseUrl;
  final String apiType;
  final String model;
  final bool thinking;
  final bool tools;
  final String systemPrompt;

  LifeRecordAiConfig copyWith({
    bool? enabled,
    String? apiKey,
    String? baseUrl,
    String? apiType,
    String? model,
    bool? thinking,
    bool? tools,
    String? systemPrompt,
  }) {
    return LifeRecordAiConfig(
      enabled: enabled ?? this.enabled,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      apiType: apiType ?? this.apiType,
      model: model ?? this.model,
      thinking: thinking ?? this.thinking,
      tools: tools ?? this.tools,
      systemPrompt: systemPrompt ?? this.systemPrompt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'apiKey': apiKey,
    'baseUrl': baseUrl,
    'apiType': apiType,
    'model': model,
    'thinking': thinking,
    'tools': tools,
    'systemPrompt': systemPrompt,
  };

  factory LifeRecordAiConfig.fromJson(Object? value) {
    final json = value is Map ? value : const <String, Object?>{};
    return LifeRecordAiConfig(
      enabled: _bool(json['enabled'], false),
      apiKey: _string(json['apiKey'], ''),
      baseUrl: _string(json['baseUrl'], 'https://api.openai.com'),
      apiType: _string(json['apiType'], 'chat_completions'),
      model: _string(json['model'], 'gpt-4o-mini'),
      thinking: _bool(json['thinking'], true),
      tools: _bool(json['tools'], true),
      systemPrompt: _string(json['systemPrompt'], ''),
    );
  }
}

class LifeRecordRuntimeConfig {
  const LifeRecordRuntimeConfig({
    this.title = '人生记录',
    this.root = 'temp/summary',
    this.host = '127.0.0.1',
    this.port = 8080,
    this.dataDir = 'data',
    this.mode = 'preview',
    this.baseUrl = '',
    this.comments = true,
    this.refresh = '2s',
    this.passwordEnv = '',
    this.password = '',
    this.excludeDirs = const <String>[],
    this.ai = const LifeRecordAiConfig(),
  });

  final String title;
  final String root;
  final String host;
  final int port;
  final String dataDir;
  final String mode;
  final String baseUrl;
  final bool comments;
  final String refresh;
  final String passwordEnv;
  final String password;
  final List<String> excludeDirs;
  final LifeRecordAiConfig ai;

  LifeRecordRuntimeConfig copyWith({
    String? title,
    String? root,
    String? host,
    int? port,
    String? dataDir,
    String? mode,
    String? baseUrl,
    bool? comments,
    String? refresh,
    String? passwordEnv,
    String? password,
    List<String>? excludeDirs,
    LifeRecordAiConfig? ai,
  }) {
    return LifeRecordRuntimeConfig(
      title: title ?? this.title,
      root: root ?? this.root,
      host: host ?? this.host,
      port: port ?? this.port,
      dataDir: dataDir ?? this.dataDir,
      mode: mode ?? this.mode,
      baseUrl: baseUrl ?? this.baseUrl,
      comments: comments ?? this.comments,
      refresh: refresh ?? this.refresh,
      passwordEnv: passwordEnv ?? this.passwordEnv,
      password: password ?? this.password,
      excludeDirs: excludeDirs ?? this.excludeDirs,
      ai: ai ?? this.ai,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'root': root,
    'host': host,
    'port': port,
    'dataDir': dataDir,
    'mode': mode,
    'baseUrl': baseUrl,
    'comments': comments,
    'refresh': refresh,
    'passwordEnv': passwordEnv,
    'password': password,
    'excludeDirs': excludeDirs,
    'ai': ai.toJson(),
  };

  factory LifeRecordRuntimeConfig.fromJson(Object? value) {
    final json = value is Map ? value : const <String, Object?>{};
    final excludes = json['excludeDirs'];
    return LifeRecordRuntimeConfig(
      title: _string(json['title'], '人生记录'),
      root: _string(json['root'], 'temp/summary'),
      host: _string(json['host'], '127.0.0.1'),
      port: _int(json['port'], 8080),
      dataDir: _string(json['dataDir'], 'data'),
      mode: _string(json['mode'], 'preview'),
      baseUrl: _optionalString(json['baseUrl']),
      comments: _bool(json['comments'], true),
      refresh: _string(json['refresh'], '2s'),
      passwordEnv: _optionalString(json['passwordEnv']),
      password: _string(json['password'], ''),
      excludeDirs: excludes is List
          ? excludes
                .map((item) => item.toString())
                .where((item) => item.isNotEmpty)
                .toList()
          : const <String>[],
      ai: LifeRecordAiConfig.fromJson(json['ai']),
    );
  }
}

class LifeRuntimeConfig {
  const LifeRuntimeConfig({
    this.mindGit = const MindGitRuntimeConfig(),
    this.lifeRecord = const LifeRecordRuntimeConfig(),
  });

  final MindGitRuntimeConfig mindGit;
  final LifeRecordRuntimeConfig lifeRecord;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'mindgit': mindGit.toJson(),
    'liferecord': lifeRecord.toJson(),
  };

  String encode() => jsonEncode(toJson());

  factory LifeRuntimeConfig.fromJson(Object? value) {
    final json = value is Map ? value : const <String, Object?>{};
    return LifeRuntimeConfig(
      mindGit: MindGitRuntimeConfig.fromJson(json['mindgit']),
      lifeRecord: LifeRecordRuntimeConfig.fromJson(json['liferecord']),
    );
  }

  factory LifeRuntimeConfig.decode(String encoded) {
    return LifeRuntimeConfig.fromJson(jsonDecode(encoded));
  }
}

String _string(Object? value, String fallback) {
  return value is String && value.trim().isNotEmpty ? value : fallback;
}

int _int(Object? value, int fallback) {
  return value is num ? value.toInt() : fallback;
}

bool _bool(Object? value, bool fallback) {
  return value is bool ? value : fallback;
}

String _optionalString(Object? value) => value is String ? value.trim() : '';
