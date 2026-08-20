import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import '../domain/life_runtime_config.dart';

class LifeRuntimeFileConfigCodec {
  const LifeRuntimeFileConfigCodec();

  LifeRuntimeConfig merge(
    LifeRuntimeConfig hostConfig,
    Map<String, Object?> fileConfig,
  ) {
    final workspaceRoot = fileConfig['workspaceRoot']?.toString() ?? '';
    final mindGit = _mergeMindGit(
      hostConfig.mindGit,
      _map(fileConfig['mindgit']),
      workspaceRoot,
    );
    final yamlText = fileConfig['liferecordYaml']?.toString() ?? '';
    return LifeRuntimeConfig(
      mindGit: mindGit,
      lifeRecord: yamlText.trim().isEmpty
          ? hostConfig.lifeRecord
          : _mergeLifeRecord(
              hostConfig.lifeRecord,
              _parseYaml(yamlText),
              workspaceRoot,
            ),
    );
  }

  MindGitRuntimeConfig _mergeMindGit(
    MindGitRuntimeConfig base,
    Map<String, Object?> config,
    String workspaceRoot,
  ) {
    if (config.isEmpty) return base;
    final server = _map(config['server']);
    final projects = _list(config['projects']);
    final directories = projects
        .map(_map)
        .map((project) => project['path']?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .map(
          (value) => _workspaceRelative(
            value,
            workspaceRoot,
            migrateLegacyDefault: true,
          ),
        )
        .toList();
    return base.copyWith(
      host: _nonEmptyString(server['bind'], base.host),
      port: _positiveInt(server['port'], base.port),
      workspace: './',
      directories: directories.isEmpty ? const <String>['./'] : directories,
    );
  }

  LifeRecordRuntimeConfig _mergeLifeRecord(
    LifeRecordRuntimeConfig base,
    Map<String, Object?> config,
    String workspaceRoot,
  ) {
    if (config.isEmpty) return base;
    final aiFile = _map(config['ai']);
    final ai = _mergeCurrentAiProfile(base.ai, aiFile);
    return base.copyWith(
      title: _nonEmptyString(config['title'], base.title),
      root: _workspaceRelative(
        _nonEmptyString(config['root'], base.root),
        workspaceRoot,
      ),
      host: _nonEmptyString(config['host'], base.host),
      port: _positiveInt(config['port'], base.port),
      dataDir: _workspaceRelative(
        _nonEmptyString(config['data_dir'], base.dataDir),
        workspaceRoot,
      ),
      mode: _nonEmptyString(config['mode'], base.mode),
      baseUrl: _string(config['base_url'], base.baseUrl),
      comments: _bool(config['comments'], base.comments),
      refresh: _nonEmptyString(config['refresh'], base.refresh),
      passwordEnv: _string(config['password_env'], base.passwordEnv),
      excludeDirs: _list(config['exclude_dirs'])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      ai: ai,
    );
  }

  LifeRecordAiConfig _mergeCurrentAiProfile(
    LifeRecordAiConfig base,
    Map<String, Object?> file,
  ) {
    if (file.isEmpty) return base;
    final profiles = base.profiles.isEmpty
        ? <LifeRecordAiProfile>[
            LifeRecordAiProfile(
              id: 'default',
              name: '默认',
              apiKey: base.apiKey,
              baseUrl: base.baseUrl,
              apiType: base.apiType,
              model: base.model,
            ),
          ]
        : List<LifeRecordAiProfile>.from(base.profiles);
    final activeId =
        profiles.any((profile) => profile.id == base.activeProfileId)
        ? base.activeProfileId
        : profiles.first.id;
    final index = profiles.indexWhere((profile) => profile.id == activeId);
    final current = profiles[index];
    final updated = LifeRecordAiProfile(
      id: current.id,
      name: current.name,
      apiKey: _string(file['api_key'] ?? file['key'], current.apiKey),
      baseUrl: _nonEmptyString(file['base_url'], current.baseUrl),
      apiType: _nonEmptyString(
        file['api_type'] ?? file['endpoint_type'],
        current.apiType,
      ),
      model: _nonEmptyString(file['model'], current.model),
    );
    profiles[index] = updated;
    return base.copyWith(
      enabled: _bool(file['enabled'], base.enabled),
      apiKey: updated.apiKey,
      baseUrl: updated.baseUrl,
      apiType: updated.apiType,
      model: updated.model,
      thinking: _bool(file['thinking'], base.thinking),
      tools: _bool(file['tools'], base.tools),
      systemPrompt: _string(file['system_prompt'], base.systemPrompt),
      activeProfileId: activeId,
      profiles: profiles,
    );
  }

  Map<String, Object?> _parseYaml(String value) {
    try {
      return _map(_plainYaml(loadYaml(value)));
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  Object? _plainYaml(Object? value) {
    if (value is YamlMap) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): _plainYaml(entry.value),
      };
    }
    if (value is YamlList) return value.map(_plainYaml).toList();
    return value;
  }

  String _workspaceRelative(
    String value,
    String workspaceRoot, {
    bool migrateLegacyDefault = false,
  }) {
    final normalized = value.trim();
    if (workspaceRoot.isEmpty || !path.posix.isAbsolute(normalized)) {
      return normalized;
    }
    final root = path.posix.normalize(workspaceRoot);
    final absolute = path.posix.normalize(normalized);
    if (absolute == root) return './';
    if (!path.posix.isWithin(root, absolute)) return normalized;
    final relative = path.posix.relative(absolute, from: root);
    if (migrateLegacyDefault && relative == 'default') return './';
    return relative;
  }

  Map<String, Object?> _map(Object? value) {
    if (value is! Map) return const <String, Object?>{};
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  List<Object?> _list(Object? value) => value is List ? value : const [];

  String _string(Object? value, String fallback) =>
      value == null ? fallback : value.toString().trim();

  String _nonEmptyString(Object? value, String fallback) {
    final result = _string(value, fallback);
    return result.isEmpty ? fallback : result;
  }

  int _positiveInt(Object? value, int fallback) {
    final result = value is num ? value.toInt() : int.tryParse('$value');
    return result != null && result > 0 ? result : fallback;
  }

  bool _bool(Object? value, bool fallback) => value is bool ? value : fallback;
}
