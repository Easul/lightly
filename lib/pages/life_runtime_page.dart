import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../features/life_runtime/infrastructure/life_runtime_plugin_gateway.dart';
import '../features/life_runtime/domain/life_runtime_config.dart';
import '../features/life_runtime/infrastructure/life_runtime_config_store.dart';
import '../services/app_toast.dart';

class LifeRuntimePage extends StatefulWidget {
  const LifeRuntimePage({super.key});

  @override
  State<LifeRuntimePage> createState() => _LifeRuntimePageState();
}

class _LifeRuntimePageState extends State<LifeRuntimePage> {
  final LifeRuntimePluginGateway _gateway = LifeRuntimePluginGateway();
  final LifeRuntimeConfigStore _configStore = LifeRuntimeConfigStore();
  Map<String, Object?> _status = const <String, Object?>{};
  LifeRuntimeConfig _config = const LifeRuntimeConfig();
  late final TextEditingController _mindGitPortController;
  late final TextEditingController _mindGitPasswordController;
  late final TextEditingController _mindGitDirectoriesController;
  late final TextEditingController _lifeTitleController;
  late final TextEditingController _lifeRootController;
  late final TextEditingController _lifePortController;
  late final TextEditingController _lifeDataDirController;
  late final TextEditingController _lifeModeController;
  late final TextEditingController _lifeBaseUrlController;
  late final TextEditingController _lifeRefreshController;
  late final TextEditingController _lifePasswordController;
  late final TextEditingController _lifePasswordEnvController;
  late final TextEditingController _lifeExcludeDirsController;
  late final TextEditingController _aiKeyController;
  late final TextEditingController _aiProfileNameController;
  late final TextEditingController _aiBaseUrlController;
  late final TextEditingController _aiTypeController;
  late final TextEditingController _aiModelController;
  late final TextEditingController _aiPromptController;
  bool _lifeComments = true;
  bool _aiEnabled = false;
  bool _aiThinking = true;
  bool _aiTools = true;
  List<LifeRecordAiProfile> _aiProfiles = const <LifeRecordAiProfile>[];
  String _activeAiProfileId = '';
  bool _busy = false;
  bool _allowLan = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _mindGitPortController = TextEditingController();
    _mindGitPasswordController = TextEditingController();
    _mindGitDirectoriesController = TextEditingController();
    _lifeTitleController = TextEditingController();
    _lifeRootController = TextEditingController();
    _lifePortController = TextEditingController();
    _lifeDataDirController = TextEditingController();
    _lifeModeController = TextEditingController();
    _lifeBaseUrlController = TextEditingController();
    _lifeRefreshController = TextEditingController();
    _lifePasswordController = TextEditingController();
    _lifePasswordEnvController = TextEditingController();
    _lifeExcludeDirsController = TextEditingController();
    _aiKeyController = TextEditingController();
    _aiProfileNameController = TextEditingController();
    _aiBaseUrlController = TextEditingController();
    _aiTypeController = TextEditingController();
    _aiModelController = TextEditingController();
    _aiPromptController = TextEditingController();
    unawaited(_loadConfig());
    unawaited(_refresh());
    _statusTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refresh()),
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    for (final controller in <TextEditingController>[
      _mindGitPortController,
      _mindGitPasswordController,
      _mindGitDirectoriesController,
      _lifeTitleController,
      _lifeRootController,
      _lifePortController,
      _lifeDataDirController,
      _lifeModeController,
      _lifeBaseUrlController,
      _lifeRefreshController,
      _lifePasswordController,
      _lifePasswordEnvController,
      _lifeExcludeDirsController,
      _aiKeyController,
      _aiProfileNameController,
      _aiBaseUrlController,
      _aiTypeController,
      _aiModelController,
      _aiPromptController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final config = await _configStore.load();
    if (!mounted) return;
    _config = config;
    _allowLan =
        config.mindGit.host == '0.0.0.0' || config.lifeRecord.host == '0.0.0.0';
    _mindGitPortController.text = config.mindGit.port.toString();
    _mindGitPasswordController.text = config.mindGit.password;
    _mindGitDirectoriesController.text = config.mindGit.directories.join(', ');
    final life = config.lifeRecord;
    _lifeTitleController.text = life.title;
    _lifeRootController.text = life.root;
    _lifePortController.text = life.port.toString();
    _lifeDataDirController.text = life.dataDir;
    _lifeModeController.text = life.mode;
    _lifeBaseUrlController.text = life.baseUrl;
    _lifeRefreshController.text = life.refresh;
    _lifePasswordController.text = life.password;
    _lifePasswordEnvController.text = life.passwordEnv;
    _lifeExcludeDirsController.text = life.excludeDirs.join(', ');
    _aiProfiles = life.ai.profiles.isEmpty
        ? <LifeRecordAiProfile>[
            LifeRecordAiProfile(
              id: 'default',
              name: '默认',
              apiKey: life.ai.apiKey,
              baseUrl: life.ai.baseUrl,
              apiType: life.ai.apiType,
              model: life.ai.model,
            ),
          ]
        : List<LifeRecordAiProfile>.from(life.ai.profiles);
    _activeAiProfileId =
        _aiProfiles.any((profile) => profile.id == life.ai.activeProfileId)
        ? life.ai.activeProfileId
        : _aiProfiles.first.id;
    _loadAiProfile(_activeAiProfileId);
    _aiPromptController.text = life.ai.systemPrompt;
    setState(() {
      _lifeComments = life.comments;
      _aiEnabled = life.ai.enabled;
      _aiThinking = life.ai.thinking;
      _aiTools = life.ai.tools;
    });
  }

  void _loadAiProfile(String id) {
    final profile = _aiProfiles.firstWhere((item) => item.id == id);
    _aiProfileNameController.text = profile.name;
    _aiKeyController.text = profile.apiKey;
    _aiBaseUrlController.text = profile.baseUrl;
    _aiTypeController.text = profile.apiType;
    _aiModelController.text = profile.model;
  }

  void _storeCurrentAiProfile() {
    final index = _aiProfiles.indexWhere(
      (profile) => profile.id == _activeAiProfileId,
    );
    if (index < 0) return;
    final updated = LifeRecordAiProfile(
      id: _activeAiProfileId,
      name: _textOr(_aiProfileNameController.text, '未命名方案'),
      apiKey: _aiKeyController.text.trim(),
      baseUrl: _textOr(_aiBaseUrlController.text, 'https://api.openai.com'),
      apiType: _textOr(_aiTypeController.text, 'chat_completions'),
      model: _textOr(_aiModelController.text, 'gpt-4o-mini'),
    );
    _aiProfiles = List<LifeRecordAiProfile>.from(_aiProfiles)
      ..[index] = updated;
  }

  void _selectAiProfile(String id) {
    if (id == _activeAiProfileId) return;
    _storeCurrentAiProfile();
    setState(() {
      _activeAiProfileId = id;
      _loadAiProfile(id);
    });
    unawaited(_saveConfig(notify: false));
  }

  void _addAiProfile() {
    _storeCurrentAiProfile();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final profile = LifeRecordAiProfile(
      id: id,
      name: '新方案 ${_aiProfiles.length + 1}',
    );
    setState(() {
      _aiProfiles = <LifeRecordAiProfile>[..._aiProfiles, profile];
      _activeAiProfileId = id;
      _loadAiProfile(id);
    });
    unawaited(_saveConfig(notify: false));
  }

  void _deleteAiProfile() {
    if (_aiProfiles.length <= 1) return;
    final remaining = _aiProfiles
        .where((profile) => profile.id != _activeAiProfileId)
        .toList();
    setState(() {
      _aiProfiles = remaining;
      _activeAiProfileId = remaining.first.id;
      _loadAiProfile(_activeAiProfileId);
    });
    unawaited(_saveConfig(notify: false));
  }

  bool _validateMindGitPassword() {
    if (_mindGitPasswordController.text.trim().length >= 8) return true;
    unawaited(AppToast.show('MindGit 访问密码至少需要 8 个字符'));
    return false;
  }

  Future<bool> _saveConfig({bool notify = true}) async {
    final old = _config;
    const defaults = LifeRuntimeConfig();
    _storeCurrentAiProfile();
    final selectedAi = _aiProfiles.firstWhere(
      (profile) => profile.id == _activeAiProfileId,
    );
    final lifeAi = old.lifeRecord.ai.copyWith(
      enabled: _aiEnabled,
      apiKey: selectedAi.apiKey,
      baseUrl: selectedAi.baseUrl,
      apiType: selectedAi.apiType,
      model: selectedAi.model,
      thinking: _aiThinking,
      tools: _aiTools,
      systemPrompt: _aiPromptController.text,
      activeProfileId: _activeAiProfileId,
      profiles: _aiProfiles,
    );
    final config = LifeRuntimeConfig(
      mindGit: old.mindGit.copyWith(
        host: _allowLan ? '0.0.0.0' : '127.0.0.1',
        port:
            int.tryParse(_mindGitPortController.text) ?? defaults.mindGit.port,
        password: _mindGitPasswordController.text,
        directories: () {
          final values = _mindGitDirectoriesController.text
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList();
          return values.isEmpty ? const <String>['./'] : values;
        }(),
      ),
      lifeRecord: old.lifeRecord.copyWith(
        host: _allowLan ? '0.0.0.0' : '127.0.0.1',
        title: _textOr(_lifeTitleController.text, defaults.lifeRecord.title),
        root: _textOr(_lifeRootController.text, defaults.lifeRecord.root),
        port:
            int.tryParse(_lifePortController.text) ?? defaults.lifeRecord.port,
        dataDir: _textOr(
          _lifeDataDirController.text,
          defaults.lifeRecord.dataDir,
        ),
        mode: _textOr(_lifeModeController.text, defaults.lifeRecord.mode),
        baseUrl: _lifeBaseUrlController.text.trim(),
        comments: _lifeComments,
        refresh: _textOr(
          _lifeRefreshController.text,
          defaults.lifeRecord.refresh,
        ),
        passwordEnv: _lifePasswordEnvController.text.trim(),
        password: _lifePasswordController.text,
        excludeDirs: _lifeExcludeDirsController.text
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(),
        ai: lifeAi,
      ),
    );
    await _configStore.save(config);
    if (mounted) {
      setState(() => _config = config);
      if (notify) unawaited(AppToast.show('运行时配置已保存；重启服务后生效'));
    }
    return true;
  }

  Future<void> _refresh() async {
    try {
      final status = await _gateway.status();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      // The platform gateway reports a useful error when the companion is absent.
    }
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final raw = await action();
      final result = jsonDecode(raw);
      if (result is Map && result['error'] != null) {
        throw StateError(result['error'].toString());
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _refresh();
    } catch (error) {
      unawaited(AppToast.show('运行时操作失败：$error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _configField(
    TextEditingController controller,
    String label, {
    bool obscureText = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        maxLines: obscureText ? 1 : maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  String _textOr(String value, String fallback) {
    final normalized = value.trim();
    return normalized.isEmpty ? fallback : normalized;
  }

  Map<String, dynamic> _running() {
    final value = _status['running'];
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    final running = _running();
    return Scaffold(
      appBar: AppBar(title: const Text('人生知识库运行时')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _RuntimeCard(
            title: '插件状态',
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      _status.isEmpty
                          ? Icons.help_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_status.isEmpty ? '未连接运行时插件' : '运行时插件已连接'),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _allowLan,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _allowLan = value),
                  title: const Text('允许局域网访问'),
                  subtitle: const Text('启动时监听 0.0.0.0；如有需要请设置访问密码'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _RuntimeCard(
            title: 'MindGit 配置',
            child: Column(
              children: [
                _configField(
                  _mindGitPortController,
                  '端口',
                  keyboardType: TextInputType.number,
                ),
                _configField(
                  _mindGitPasswordController,
                  '访问密码',
                  obscureText: true,
                ),
                _configField(
                  _mindGitDirectoriesController,
                  '项目目录（相对运行时根目录，逗号分隔）',
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '项目目录相对于运行目录的 workspaces 子目录；./ 表示整个 workspace。访问密码必填且至少 8 个字符。',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: _busy ? null : _saveConfig,
                    child: const Text('保存 MindGit 配置'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _RuntimeCard(
            title: 'Life Record 配置',
            child: Column(
              children: [
                _configField(_lifeTitleController, '标题'),
                _configField(_lifeRootController, '内容目录'),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('内容目录相对于运行目录的 workspaces 子目录。'),
                  ),
                ),
                _configField(
                  _lifePortController,
                  '端口',
                  keyboardType: TextInputType.number,
                ),
                _configField(_lifeDataDirController, '数据目录'),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('数据目录相对于运行目录的 workspaces 子目录。'),
                  ),
                ),
                _configField(_lifeModeController, '模式（preview / public）'),
                _configField(_lifeBaseUrlController, 'Base URL'),
                _configField(_lifeRefreshController, '刷新间隔'),
                _configField(_lifePasswordEnvController, '密码环境变量'),
                _configField(
                  _lifePasswordController,
                  '访问密码',
                  obscureText: true,
                ),
                _configField(_lifeExcludeDirsController, '排除目录（逗号分隔）'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用评论'),
                  value: _lifeComments,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _lifeComments = value),
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: const Text('AI 配置'),
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用 AI'),
                      value: _aiEnabled,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _aiEnabled = value),
                    ),
                    if (_aiProfiles.isNotEmpty)
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey<String>(_activeAiProfileId),
                              initialValue: _activeAiProfileId,
                              decoration: const InputDecoration(
                                labelText: '上游方案',
                                border: OutlineInputBorder(),
                              ),
                              items: _aiProfiles
                                  .map(
                                    (profile) => DropdownMenuItem<String>(
                                      value: profile.id,
                                      child: Text(profile.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _busy
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        _selectAiProfile(value);
                                      }
                                    },
                            ),
                          ),
                          IconButton(
                            tooltip: '新增上游方案',
                            onPressed: _busy ? null : _addAiProfile,
                            icon: const Icon(Icons.add_rounded),
                          ),
                          IconButton(
                            tooltip: '删除当前方案',
                            onPressed: _busy || _aiProfiles.length <= 1
                                ? null
                                : _deleteAiProfile,
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    _configField(_aiProfileNameController, '方案名称'),
                    _configField(
                      _aiKeyController,
                      'API Key',
                      obscureText: true,
                    ),
                    _configField(_aiBaseUrlController, 'API Base URL'),
                    _configField(_aiTypeController, 'API 类型'),
                    _configField(_aiModelController, '模型'),
                    _configField(_aiPromptController, '系统提示词', maxLines: 3),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Thinking'),
                      value: _aiThinking,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _aiThinking = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tools'),
                      value: _aiTools,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _aiTools = value),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: _busy ? null : _saveConfig,
                    child: const Text('保存 Life Record 配置'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ServiceCard(
            title: 'MindGit',
            serviceId: 'mindgit',
            running: running['mindgit'],
            busy: _busy,
            onStart: () => _run(() async {
              if (!_validateMindGitPassword()) return '{}';
              if (!await _saveConfig(notify: false)) return '{}';
              return _gateway.start(
                'mindgit',
                host: _config.mindGit.host,
                allowLan: _allowLan,
                port: int.tryParse(_mindGitPortController.text),
                workspace: _config.mindGit.workspace,
                settings: <String, Object?>{
                  'root': _textOr(_config.mindGit.workspace, 'default'),
                  'password': _mindGitPasswordController.text,
                  'directories': _config.mindGit.directories,
                },
              );
            }),
            onRestart: () => _run(() async {
              if (!_validateMindGitPassword()) return '{}';
              await _gateway.stop('mindgit');
              if (!await _saveConfig(notify: false)) return '{}';
              return _gateway.start(
                'mindgit',
                host: _config.mindGit.host,
                allowLan: _allowLan,
                port: _config.mindGit.port,
                workspace: _config.mindGit.workspace,
                settings: <String, Object?>{
                  'password': _config.mindGit.password,
                  'directories': _config.mindGit.directories,
                },
              );
            }),
            onStop: () => _run(() async {
              await _gateway.stop('mindgit');
              return '{}';
            }),
          ),
          const SizedBox(height: 12),
          _ServiceCard(
            title: 'Life Record',
            serviceId: 'liferecord',
            running: running['liferecord'],
            busy: _busy,
            onStart: () => _run(() async {
              if (!await _saveConfig(notify: false)) return '{}';
              return _gateway.start(
                'liferecord',
                host: _config.lifeRecord.host,
                allowLan: _allowLan,
                port: int.tryParse(_lifePortController.text),
                workspace: _config.lifeRecord.root,
                settings: <String, Object?>{
                  'root': _textOr(_lifeRootController.text, 'summary'),
                  'title': _textOr(_lifeTitleController.text, '人生记录'),
                  'dataDir': _textOr(
                    _lifeDataDirController.text,
                    'life-record/data',
                  ),
                  'mode': _textOr(_lifeModeController.text, 'preview'),
                  'baseUrl': _lifeBaseUrlController.text.trim(),
                  'comments': _lifeComments,
                  'refresh': _textOr(_lifeRefreshController.text, '2s'),
                  'passwordEnv': _lifePasswordEnvController.text.trim(),
                  'password': _lifePasswordController.text,
                  'excludeDirs': _config.lifeRecord.excludeDirs,
                  'ai': _config.lifeRecord.ai.toJson(),
                },
              );
            }),
            onRestart: () => _run(() async {
              await _gateway.stop('liferecord');
              if (!await _saveConfig(notify: false)) return '{}';
              final life = _config.lifeRecord;
              return _gateway.start(
                'liferecord',
                host: life.host,
                allowLan: _allowLan,
                port: life.port,
                workspace: life.root,
                settings: <String, Object?>{
                  'root': life.root,
                  'title': life.title,
                  'dataDir': life.dataDir,
                  'mode': life.mode,
                  'baseUrl': life.baseUrl,
                  'comments': life.comments,
                  'refresh': life.refresh,
                  'passwordEnv': life.passwordEnv,
                  'password': life.password,
                  'excludeDirs': life.excludeDirs,
                  'ai': life.ai.toJson(),
                },
              );
            }),
            onStop: () => _run(() async {
              await _gateway.stop('liferecord');
              return '{}';
            }),
          ),
          if (_status['runtimeRoot'] case final String root) ...[
            const SizedBox(height: 12),
            Text('运行目录：$root', style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _RuntimeCard extends StatelessWidget {
  const _RuntimeCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.title,
    required this.serviceId,
    required this.running,
    required this.busy,
    required this.onStart,
    required this.onRestart,
    required this.onStop,
  });

  final String title;
  final String serviceId;
  final dynamic running;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onRestart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final data = running is Map
        ? running.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final isRunning = data['running'] == true;
    final url = data['url']?.toString();
    return _RuntimeCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isRunning ? '运行中' : '未启动'),
          if (isRunning && url != null) ...[
            const SizedBox(height: 6),
            SelectableText(url),
            if (data['password'] case final String password)
              SelectableText('局域网密码：$password'),
          ],
          if (!isRunning && data['exitCode'] != null) ...[
            const SizedBox(height: 6),
            Text('上次启动失败（退出码 ${data['exitCode']}）'),
            if (data['lastLog'] case final String log when log.isNotEmpty)
              SelectableText(log, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: busy ? null : (isRunning ? onRestart : onStart),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(isRunning ? '重启' : '启动'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: busy || !isRunning ? null : onStop,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('停止'),
              ),
            ],
          ),
          if (serviceId.isNotEmpty && !isRunning) ...[
            const SizedBox(height: 6),
            Text('默认仅监听本机回环地址', style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
