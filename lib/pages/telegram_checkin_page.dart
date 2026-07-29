import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_toast.dart';
import '../features/telegram/telegram_checkin_models.dart';
import '../features/telegram/telegram_checkin_store.dart';
import '../features/telegram/telegram_tdlib_service.dart';
import '../widgets/telegram_chats_pane.dart';

class TelegramCheckinPage extends StatefulWidget {
  const TelegramCheckinPage({super.key});

  @override
  State<TelegramCheckinPage> createState() => _TelegramCheckinPageState();
}

class _TelegramCheckinPageState extends State<TelegramCheckinPage> {
  final TelegramCheckinStore _store = TelegramCheckinStore();
  final TelegramTdlibService _telegram = TelegramTdlibService.instance;
  TelegramCheckinConfig _config = const TelegramCheckinConfig();
  List<TelegramMessagePreview> _messages = const [];
  final Map<String, String> _results = <String, String>{};
  bool _loading = true;
  bool _busy = false;
  String? _selectedTargetId;

  @override
  void initState() {
    super.initState();
    _telegram.authStep.addListener(_onAuthChanged);
    _telegram.proxyStatus.addListener(_onAuthChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _telegram.authStep.removeListener(_onAuthChanged);
    _telegram.proxyStatus.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final config = await _store.load();
    if (!mounted) return;
    setState(() {
      _config = config;
      _selectedTargetId = config.targets.firstOrNull?.id;
      _loading = false;
    });
    if (config.hasApiCredentials) {
      try {
        await _telegram.start(config);
      } catch (error) {
        _toast('Telegram 初始化失败：$error');
      }
    }
  }

  void _toast(String message) => unawaited(AppToast.show(message));

  Future<void> _editApiConfig() async {
    final apiIdController = TextEditingController(
      text: _config.apiId == 0 ? '' : _config.apiId.toString(),
    );
    final apiHashController = TextEditingController(text: _config.apiHash);
    final phoneController = TextEditingController(text: _config.phoneNumber);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Telegram API 配置'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: apiIdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'App ID'),
              ),
              TextField(
                controller: apiHashController,
                decoration: const InputDecoration(labelText: 'App Hash'),
              ),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: '手机号',
                  hintText: '+8613800000000',
                ),
              ),
              const SizedBox(height: 8),
              const Text('这些配置会包含在应用备份中，请妥善保存备份文件。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final apiId = int.tryParse(apiIdController.text.trim()) ?? 0;
    final updated = _config.copyWith(
      apiId: apiId,
      apiHash: apiHashController.text.trim(),
      phoneNumber: phoneController.text.trim(),
    );
    await _store.save(updated);
    if (!mounted) return;
    setState(() => _config = updated);
    try {
      await _telegram.start(updated);
    } catch (error) {
      _toast('Telegram 初始化失败：$error');
    }
  }

  Future<void> _submitAuthValue(String title, bool obscure) async {
    final controller = TextEditingController(
      text: _telegram.authStep.value == TelegramAuthStep.phone
          ? _config.phoneNumber
          : '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: obscure,
          autofocus: true,
          keyboardType: title.contains('手机号')
              ? TextInputType.phone
              : TextInputType.text,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    if (value == null || value.trim().isEmpty) return;
    try {
      switch (_telegram.authStep.value) {
        case TelegramAuthStep.phone:
          await _telegram.submitPhone(value.trim());
        case TelegramAuthStep.code:
          await _telegram.submitCode(value.trim());
        case TelegramAuthStep.password:
          await _telegram.submitPassword(value);
        default:
          break;
      }
    } catch (error) {
      _toast('登录失败：$error');
    }
  }

  Future<void> _addTarget() async {
    final usernameController = TextEditingController();
    final commandController = TextEditingController(text: '/checkin');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加签到目标'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(labelText: '@机器人或公开群组'),
            ),
            TextField(
              controller: commandController,
              decoration: const InputDecoration(labelText: '签到命令'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    final username = usernameController.text.trim();
    final command = commandController.text.trim();
    if (confirmed != true || username.isEmpty || command.isEmpty) return;
    final target = TelegramCheckinTarget(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      username: username.startsWith('@') ? username : '@$username',
      command: command,
    );
    final updated = _config.copyWith(targets: [..._config.targets, target]);
    await _store.save(updated);
    if (!mounted) return;
    setState(() {
      _config = updated;
      _selectedTargetId ??= target.id;
    });
  }

  Future<void> _deleteTarget(TelegramCheckinTarget target) async {
    final updated = _config.copyWith(
      targets: _config.targets.where((item) => item.id != target.id).toList(),
    );
    await _store.save(updated);
    if (!mounted) return;
    setState(() {
      _config = updated;
      if (_selectedTargetId == target.id) {
        _selectedTargetId = updated.targets.firstOrNull?.id;
        _messages = const [];
      }
    });
  }

  Future<void> _setTargetEnabled(
    TelegramCheckinTarget target,
    bool enabled,
  ) async {
    final updated = _config.copyWith(
      targets: _config.targets
          .map(
            (item) =>
                item.id == target.id ? item.copyWith(enabled: enabled) : item,
          )
          .toList(),
    );
    await _store.save(updated);
    if (mounted) setState(() => _config = updated);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出 Telegram'),
        content: const Text('将删除本机 Telegram 登录会话，签到配置会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _telegram.logout();
      _toast('已退出 Telegram');
    } catch (error) {
      _toast('退出失败：$error');
    }
  }

  Future<void> _restartLogin() async {
    try {
      await _telegram.start(_config);
    } catch (error) {
      _toast('重新登录失败：$error');
    }
  }

  Future<void> _refreshMessages() async {
    final target = _selectedTarget;
    if (target == null) return;
    setState(() => _busy = true);
    try {
      final messages = await _telegram.fetchLatest(target.username);
      if (mounted) setState(() => _messages = messages);
    } catch (error) {
      _toast('刷新失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runAll() async {
    setState(() {
      _busy = true;
      _results.clear();
    });
    for (final target in _config.targets.where((item) => item.enabled)) {
      if (!mounted) break;
      setState(() => _results[target.id] = '发送中');
      try {
        await _telegram.sendCommand(target.username, target.command);
        if (mounted) setState(() => _results[target.id] = '发送成功');
      } catch (error) {
        if (mounted) setState(() => _results[target.id] = '失败：$error');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (mounted) setState(() => _busy = false);
  }

  TelegramCheckinTarget? get _selectedTarget => _config.targets
      .where((target) => target.id == _selectedTargetId)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('TG 工具'),
          actions: [
            if (_telegram.authStep.value == TelegramAuthStep.ready)
              IconButton(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded),
                tooltip: '退出 Telegram',
              ),
            IconButton(
              onPressed: _editApiConfig,
              icon: const Icon(Icons.settings_rounded),
              tooltip: 'API 配置',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.chat_bubble_outline_rounded), text: '会话'),
              Tab(icon: Icon(Icons.task_alt_rounded), text: '签到'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  const TelegramChatsPane(),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildLoginCard(),
                      const SizedBox(height: 12),
                      _buildTargetsCard(),
                      const SizedBox(height: 12),
                      _buildMessagesCard(),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLoginCard() {
    final step = _telegram.authStep.value;
    final label = switch (step) {
      TelegramAuthStep.ready => '已登录',
      TelegramAuthStep.phone => '需要手机号',
      TelegramAuthStep.code => '需要验证码',
      TelegramAuthStep.password => '需要两步验证密码',
      TelegramAuthStep.loggedOut => '已退出',
      TelegramAuthStep.error => '请先配置 App ID / App Hash',
      TelegramAuthStep.loading => '正在初始化',
    };
    VoidCallback? action;
    if (step == TelegramAuthStep.phone) {
      action = () => _submitAuthValue('输入手机号', false);
    } else if (step == TelegramAuthStep.code) {
      action = () => _submitAuthValue('输入验证码', false);
    } else if (step == TelegramAuthStep.password) {
      action = () => _submitAuthValue('输入两步验证密码', true);
    } else if (step == TelegramAuthStep.error) {
      action = _editApiConfig;
    } else if (step == TelegramAuthStep.loggedOut) {
      action = _restartLogin;
    }
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.telegram),
            title: const Text('Telegram 账号'),
            subtitle: Text('$label\n${_telegram.proxyStatus.value}'),
            isThreeLine: true,
            trailing: action == null
                ? null
                : TextButton(onPressed: action, child: const Text('继续')),
          ),
          if (step == TelegramAuthStep.phone) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '首次迁移到独立插件，或卸载插件后重新安装时需登录',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTargetsCard() {
    return Card(
      child: Column(
        children: [
          ListTile(
            title: const Text('签到目标'),
            trailing: IconButton(
              onPressed: _addTarget,
              icon: const Icon(Icons.add_rounded),
            ),
          ),
          for (final target in _config.targets)
            ListTile(
              selected: target.id == _selectedTargetId,
              onTap: () => setState(() {
                _selectedTargetId = target.id;
                _messages = const [];
              }),
              title: Text(target.username),
              subtitle: Text('${target.command}  ${_results[target.id] ?? ''}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: target.enabled,
                    onChanged: (value) => _setTargetEnabled(target, value),
                  ),
                  IconButton(
                    onPressed: () => _deleteTarget(target),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
          if (_config.targets.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('添加 @机器人或公开群组以及签到命令。'),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    _busy || !_config.targets.any((target) => target.enabled)
                    ? null
                    : _runAll,
                icon: const Icon(Icons.send_rounded),
                label: const Text('一键签到'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesCard() {
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(
              _selectedTarget == null
                  ? '最近消息'
                  : '${_selectedTarget!.username} 最近消息',
            ),
            trailing: IconButton(
              onPressed: _busy || _selectedTarget == null
                  ? null
                  : _refreshMessages,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          for (final message in _messages)
            ListTile(
              dense: true,
              title: SelectableText(message.text),
              subtitle: Text(message.date.toLocal().toString()),
            ),
          if (_messages.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('选择目标后点击刷新，读取最近 10 条消息。'),
            ),
        ],
      ),
    );
  }
}
