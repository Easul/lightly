import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../features/life_runtime/infrastructure/life_runtime_plugin_gateway.dart';
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
  Map<String, Object?> _status = const <String, Object?>{};
  bool _busy = false;
  bool _allowLan = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
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
