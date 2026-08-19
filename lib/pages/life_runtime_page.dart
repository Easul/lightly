import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../features/life_runtime/infrastructure/life_runtime_plugin_gateway.dart';
import '../features/life_runtime/domain/life_runtime_config.dart';
import '../features/life_runtime/infrastructure/life_runtime_config_store.dart';
import '../features/optional_plugins/domain/optional_feature.dart';
import '../features/optional_plugins/presentation/optional_feature_gate.dart';
import '../services/app_toast.dart';

class LifeRuntimePage extends StatefulWidget {
  const LifeRuntimePage({super.key});

  @override
  State<LifeRuntimePage> createState() => _LifeRuntimePageState();
}

class _LifeRuntimePageState extends State<LifeRuntimePage> {
  final LifeRuntimePluginGateway _gateway = LifeRuntimePluginGateway();
  final OptionalFeatureGate _featureGate = OptionalFeatureGate();
  final LifeRuntimeConfigStore _configStore = LifeRuntimeConfigStore();
  Map<String, Object?> _status = const <String, Object?>{};
  LifeRuntimeConfig _config = const LifeRuntimeConfig();
  late final TextEditingController _mindGitPortController;
  late final TextEditingController _mindGitPasswordController;
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
  late final TextEditingController _aiBaseUrlController;
  late final TextEditingController _aiTypeController;
  late final TextEditingController _aiModelController;
  late final TextEditingController _aiPromptController;
  bool _lifeComments = true;
  bool _aiEnabled = false;
  bool _aiThinking = true;
  bool _aiTools = true;
  bool _busy = false;
  bool _allowLan = false;

  @override
  void initState() {
    super.initState();
    _mindGitPortController = TextEditingController();
    _mindGitPasswordController = TextEditingController();
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
    _aiBaseUrlController = TextEditingController();
    _aiTypeController = TextEditingController();
    _aiModelController = TextEditingController();
    _aiPromptController = TextEditingController();
    unawaited(_loadConfig());
    unawaited(_refresh());
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _mindGitPortController,
      _mindGitPasswordController,
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
    _mindGitPortController.text = config.mindGit.port.toString();
    _mindGitPasswordController.text = config.mindGit.password;
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
    _aiKeyController.text = life.ai.apiKey;
    _aiBaseUrlController.text = life.ai.baseUrl;
    _aiTypeController.text = life.ai.apiType;
    _aiModelController.text = life.ai.model;
    _aiPromptController.text = life.ai.systemPrompt;
    setState(() {
      _lifeComments = life.comments;
      _aiEnabled = life.ai.enabled;
      _aiThinking = life.ai.thinking;
      _aiTools = life.ai.tools;
    });
  }

  Future<void> _saveConfig() async {
    final old = _config;
    final lifeAi = old.lifeRecord.ai.copyWith(
      enabled: _aiEnabled,
      apiKey: _aiKeyController.text.trim(),
      baseUrl: _textOr(_aiBaseUrlController.text, old.lifeRecord.ai.baseUrl),
      apiType: _textOr(_aiTypeController.text, old.lifeRecord.ai.apiType),
      model: _textOr(_aiModelController.text, old.lifeRecord.ai.model),
      thinking: _aiThinking,
      tools: _aiTools,
      systemPrompt: _aiPromptController.text,
    );
    final config = LifeRuntimeConfig(
      mindGit: old.mindGit.copyWith(
        host: old.mindGit.host,
        port: int.tryParse(_mindGitPortController.text) ?? old.mindGit.port,
        password: _mindGitPasswordController.text,
      ),
      lifeRecord: old.lifeRecord.copyWith(
        title: _textOr(_lifeTitleController.text, old.lifeRecord.title),
        root: _textOr(_lifeRootController.text, old.lifeRecord.root),
        port: int.tryParse(_lifePortController.text) ?? old.lifeRecord.port,
        dataDir: _textOr(_lifeDataDirController.text, old.lifeRecord.dataDir),
        mode: _textOr(_lifeModeController.text, old.lifeRecord.mode),
        baseUrl: _textOr(_lifeBaseUrlController.text, old.lifeRecord.baseUrl),
        comments: _lifeComments,
        refresh: _textOr(_lifeRefreshController.text, old.lifeRecord.refresh),
        passwordEnv: _textOr(
          _lifePasswordEnvController.text,
          old.lifeRecord.passwordEnv,
        ),
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
      unawaited(AppToast.show('运行时配置已保存；重启服务后生效'));
    }
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
      await _refresh();
    } catch (error) {
      unawaited(AppToast.show('运行时操作失败：$error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ensurePlugin() async {
    if (!await _featureGate.ensureAvailable(
      context,
      OptionalFeatureId.lifeRuntime,
    )) {
      return;
    }
    await _refresh();
  }

  Future<void> _exportData() async {
    setState(() => _busy = true);
    try {
      await _saveConfig();
      final result = await _gateway.exportData(_config);
      if (result['error'] != null) throw StateError(result['error'].toString());
      final source = result['path']?.toString();
      if (source == null) throw StateError('导出文件未生成');
      final target = await FilePicker.platform.saveFile(
        dialogTitle: '导出人生运行时数据',
        fileName: 'life-runtime-backup.zip',
        type: FileType.any,
      );
      if (target == null || target.isEmpty) return;
      await File(source).copy(target);
      if (mounted) unawaited(AppToast.show('运行时数据已导出'));
    } catch (error) {
      if (mounted) unawaited(AppToast.show('导出失败：$error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importData() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    final path = picked != null && picked.files.isNotEmpty
        ? picked.files.first.path
        : null;
    if (path == null || path.isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await _gateway.importData(path);
      if (result['error'] != null) throw StateError(result['error'].toString());
      final configJson = result['configJson']?.toString();
      if (configJson != null) {
        final config = LifeRuntimeConfig.decode(configJson);
        await _configStore.save(config);
        if (mounted) setState(() => _config = config);
        await _loadConfig();
      }
      if (mounted) unawaited(AppToast.show('运行时数据已导入，请重新启动服务'));
    } catch (error) {
      if (mounted) unawaited(AppToast.show('导入失败：$error'));
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
      appBar: AppBar(
        title: const Text('人生知识库运行时'),
        actions: [
          IconButton(
            tooltip: '刷新状态',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
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
                    OutlinedButton(
                      onPressed: _busy ? null : _ensurePlugin,
                      child: const Text('检查'),
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
                  subtitle: const Text('启动时使用 0.0.0.0，并生成一次性访问密码'),
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
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('密码为空时关闭 MindGit 登录保护；修改后需重启服务。'),
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
                _configField(
                  _lifePortController,
                  '端口',
                  keyboardType: TextInputType.number,
                ),
                _configField(_lifeDataDirController, '数据目录'),
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
          _RuntimeCard(
            title: '数据导入导出',
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _exportData,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('导出运行时数据'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _importData,
                    icon: const Icon(Icons.download),
                    label: const Text('导入运行时数据'),
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
            onStart: () => _run(
              () => _gateway.start(
                'mindgit',
                host: _allowLan ? '0.0.0.0' : '127.0.0.1',
                allowLan: _allowLan,
                port: int.tryParse(_mindGitPortController.text),
                workspace: _config.mindGit.workspace,
                settings: <String, Object?>{
                  'root': _textOr(_config.mindGit.workspace, 'default'),
                  'password': _mindGitPasswordController.text,
                },
              ),
            ),
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
            onStart: () => _run(
              () => _gateway.start(
                'liferecord',
                host: _allowLan ? '0.0.0.0' : '127.0.0.1',
                allowLan: _allowLan,
                port: int.tryParse(_lifePortController.text),
                workspace: _config.lifeRecord.root,
                settings: <String, Object?>{
                  'root': _textOr(_lifeRootController.text, 'temp/summary'),
                  'title': _textOr(_lifeTitleController.text, '人生记录'),
                  'dataDir': _textOr(_lifeDataDirController.text, 'data'),
                  'mode': _textOr(_lifeModeController.text, 'preview'),
                  'baseUrl': _textOr(
                    _lifeBaseUrlController.text,
                    'http://127.0.0.1:8080',
                  ),
                  'comments': _lifeComments,
                  'refresh': _textOr(_lifeRefreshController.text, '2s'),
                  'passwordEnv': _textOr(
                    _lifePasswordEnvController.text,
                    'LIFERECORD_PASSWORD',
                  ),
                  'password': _lifePasswordController.text,
                  'excludeDirs': _config.lifeRecord.excludeDirs,
                  'ai': _config.lifeRecord.ai.toJson(),
                },
              ),
            ),
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
    required this.onStop,
  });

  final String title;
  final String serviceId;
  final dynamic running;
  final bool busy;
  final VoidCallback onStart;
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
          if (url != null) ...[
            const SizedBox(height: 6),
            SelectableText(url),
            if (data['password'] case final String password)
              SelectableText('局域网密码：$password'),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: busy || isRunning ? null : onStart,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('启动'),
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
