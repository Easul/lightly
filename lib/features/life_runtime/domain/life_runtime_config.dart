import 'dart:convert';

class MindGitRuntimeConfig {
  const MindGitRuntimeConfig({
    this.host = '127.0.0.1',
    this.port = 8787,
    this.password = '',
    this.workspace = 'default',
    this.directories = const <String>['./'],
  });

  final String host;
  final int port;
  final String password;
  final String workspace;
  final List<String> directories;

  MindGitRuntimeConfig copyWith({
    String? host,
    int? port,
    String? password,
    String? workspace,
    List<String>? directories,
  }) {
    return MindGitRuntimeConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      password: password ?? this.password,
      workspace: workspace ?? this.workspace,
      directories: directories ?? this.directories,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'host': host,
    'port': port,
    'password': password,
    'workspace': workspace,
    'directories': directories,
  };

  factory MindGitRuntimeConfig.fromJson(Object? value) {
    final json = value is Map ? value : const <String, Object?>{};
    final dirs = json['directories'];
    final directories = dirs is List
        ? dirs
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList()
        : <String>[];
    final workspace = _string(json['workspace'], 'default');
    return MindGitRuntimeConfig(
      host: _string(json['host'], '127.0.0.1'),
      port: _int(json['port'], 8787),
      password: _string(json['password'], ''),
      workspace: workspace,
      directories:
          directories.isEmpty ||
              (directories.length == 1 && directories.single == workspace)
          ? const <String>['./']
          : directories,
    );
  }
}

class LifeRecordAiProfile {
  const LifeRecordAiProfile({
    required this.id,
    required this.name,
    this.apiKey = '',
    this.baseUrl = 'https://api.openai.com',
    this.apiType = 'chat_completions',
    this.model = 'gpt-4o-mini',
  });

  final String id;
  final String name;
  final String apiKey;
  final String baseUrl;
  final String apiType;
  final String model;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'apiKey': apiKey,
    'baseUrl': baseUrl,
    'apiType': apiType,
    'model': model,
  };

  factory LifeRecordAiProfile.fromJson(Object? value) {
    final json = value is Map ? value : const <String, Object?>{};
    return LifeRecordAiProfile(
      id: _string(json['id'], 'default'),
      name: _string(json['name'], '默认'),
      apiKey: _optionalString(json['apiKey']),
      baseUrl: _string(json['baseUrl'], 'https://api.openai.com'),
      apiType: _string(json['apiType'], 'chat_completions'),
      model: _string(json['model'], 'gpt-4o-mini'),
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
    this.activeProfileId = '',
    this.profiles = const <LifeRecordAiProfile>[],
  });

  final bool enabled;
  final String apiKey;
  final String baseUrl;
  final String apiType;
  final String model;
  final bool thinking;
  final bool tools;
  final String systemPrompt;
  final String activeProfileId;
  final List<LifeRecordAiProfile> profiles;

  LifeRecordAiConfig copyWith({
    bool? enabled,
    String? apiKey,
    String? baseUrl,
    String? apiType,
    String? model,
    bool? thinking,
    bool? tools,
    String? systemPrompt,
    String? activeProfileId,
    List<LifeRecordAiProfile>? profiles,
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
      activeProfileId: activeProfileId ?? this.activeProfileId,
      profiles: profiles ?? this.profiles,
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
    'activeProfileId': activeProfileId,
    'profiles': profiles.map((profile) => profile.toJson()).toList(),
  };

  factory LifeRecordAiConfig.fromJson(Object? value) {
    final json = value is Map ? value : const <String, Object?>{};
    final parsedProfiles = (json['profiles'] as List? ?? const <Object?>[])
        .map(LifeRecordAiProfile.fromJson)
        .toList();
    final legacyProfile = LifeRecordAiProfile(
      id: 'default',
      name: '默认',
      apiKey: _optionalString(json['apiKey']),
      baseUrl: _string(json['baseUrl'], 'https://api.openai.com'),
      apiType: _string(json['apiType'], 'chat_completions'),
      model: _string(json['model'], 'gpt-4o-mini'),
    );
    final profiles = parsedProfiles.isEmpty
        ? <LifeRecordAiProfile>[legacyProfile]
        : parsedProfiles;
    final requestedActive = _optionalString(json['activeProfileId']);
    final active = profiles.any((profile) => profile.id == requestedActive)
        ? requestedActive
        : profiles.first.id;
    final selected = profiles.firstWhere((profile) => profile.id == active);
    return LifeRecordAiConfig(
      enabled: _bool(json['enabled'], false),
      apiKey: selected.apiKey,
      baseUrl: selected.baseUrl,
      apiType: selected.apiType,
      model: selected.model,
      thinking: _bool(json['thinking'], true),
      tools: _bool(json['tools'], true),
      systemPrompt: _string(json['systemPrompt'], ''),
      activeProfileId: active,
      profiles: profiles,
    );
  }
}

class LifeRecordRuntimeConfig {
  const LifeRecordRuntimeConfig({
    this.title = '人生记录',
    this.root = 'summary',
    this.host = '127.0.0.1',
    this.port = 8347,
    this.dataDir = 'life-record/data',
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

  factory LifeRecordRuntimeConfig.fromJson(
    Object? value, {
    bool migrateLegacyDefaults = false,
  }) {
    final json = value is Map ? value : const <String, Object?>{};
    final excludes = json['excludeDirs'];
    final storedRoot = _string(json['root'], 'summary');
    final storedPort = _int(json['port'], 8347);
    final storedBaseUrl = _optionalString(json['baseUrl']);
    final storedPasswordEnv = _optionalString(json['passwordEnv']);
    return LifeRecordRuntimeConfig(
      title: _string(json['title'], '人生记录'),
      root: migrateLegacyDefaults && storedRoot == 'temp/summary'
          ? 'summary'
          : storedRoot,
      host: _string(json['host'], '127.0.0.1'),
      port: migrateLegacyDefaults && storedPort == 8080 ? 8347 : storedPort,
      dataDir: _string(json['dataDir'], 'life-record/data'),
      mode: _string(json['mode'], 'preview'),
      baseUrl: migrateLegacyDefaults && storedBaseUrl == 'http://127.0.0.1:8080'
          ? ''
          : storedBaseUrl,
      comments: _bool(json['comments'], true),
      refresh: _string(json['refresh'], '2s'),
      passwordEnv:
          migrateLegacyDefaults && storedPasswordEnv == 'LIFERECORD_PASSWORD'
          ? ''
          : storedPasswordEnv,
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
    'version': 2,
    'mindgit': mindGit.toJson(),
    'liferecord': lifeRecord.toJson(),
  };

  String encode() => jsonEncode(toJson());

  factory LifeRuntimeConfig.fromJson(Object? value) {
    final json = value is Map ? value : const <String, Object?>{};
    return LifeRuntimeConfig(
      mindGit: MindGitRuntimeConfig.fromJson(json['mindgit']),
      lifeRecord: LifeRecordRuntimeConfig.fromJson(
        json['liferecord'],
        migrateLegacyDefaults: _int(json['version'], 1) < 2,
      ),
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
