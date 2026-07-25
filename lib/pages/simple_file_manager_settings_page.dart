import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_toast.dart';
import '../services/shared_downloads_directory_service.dart';
import '../services/simple_file_manager_service.dart';
import '../app/app_runtime_coordinator.dart';

class SimpleFileManagerSettingsPage extends StatefulWidget {
  const SimpleFileManagerSettingsPage({super.key});

  @override
  State<SimpleFileManagerSettingsPage> createState() =>
      _SimpleFileManagerSettingsPageState();
}

class _SimpleFileManagerSettingsPageState
    extends State<SimpleFileManagerSettingsPage> {
  final SimpleFileManagerService _service = SimpleFileManagerService();
  final SharedDownloadsDirectoryService _fileAccessService =
      SharedDownloadsDirectoryService();
  final TextEditingController _rootPathController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _favoritePathController = TextEditingController();

  StreamSubscription<SimpleFileManagerState>? _stateSubscription;
  SimpleFileManagerState _state = SimpleFileManagerState.stopped;
  List<String> _favoritePaths = const <String>[];
  bool _enabled = false;
  bool _bindAllInterfaces = true;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _state = _service.isRunning
        ? SimpleFileManagerState.started
        : SimpleFileManagerState.stopped;
    _stateSubscription = _service.stateStream.listen((state) {
      if (!mounted) return;
      setState(() => _state = state);
    });
    unawaited(_loadSettings());
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _rootPathController.dispose();
    _portController.dispose();
    _favoritePathController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await _service.loadSettings();
    if (!mounted) return;
    setState(() {
      _enabled = settings.enabled;
      _bindAllInterfaces = settings.bindAllInterfaces;
      _rootPathController.text = settings.rootPath;
      _portController.text = settings.port.toString();
      _favoritePaths = settings.favoritePaths;
      _busy = false;
    });
  }

  Future<void> _saveAndApply({bool? enabled}) async {
    final nextEnabled = enabled ?? _enabled;
    if (nextEnabled && !await _ensureFileAccess()) {
      setState(() => _enabled = false);
      return;
    }

    setState(() => _busy = true);
    try {
      final settings = _buildSettings(enabled: nextEnabled);
      await AppRuntimeCoordinator.instance.applySimpleFileManagerSettings(
        settings,
      );
      if (!mounted) return;
      setState(() {
        _enabled = nextEnabled;
        _favoritePaths = _service.settings.favoritePaths;
      });
      _showToast(nextEnabled ? '文件简易管理已启动' : '文件简易管理已停止');
    } catch (error) {
      if (!mounted) return;
      setState(() => _enabled = _service.isRunning);
      _showToast('保存失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _ensureFileAccess() async {
    if (!Platform.isAndroid) return true;
    if (await _fileAccessService.hasFileAccessPermission()) return true;
    final granted = await _fileAccessService.requestFileAccessPermission();
    if (!granted && mounted) {
      _showToast('需要文件访问权限才能管理 /storage/emulated/0 下的文件');
    }
    return granted;
  }

  SimpleFileManagerSettings _buildSettings({bool? enabled}) {
    final portText = _portController.text.trim();
    final parsedPort = portText.isEmpty
        ? SimpleFileManagerSettings.defaultPort
        : int.tryParse(portText);
    return SimpleFileManagerSettings(
      enabled: enabled ?? _enabled,
      rootPath: _rootPathController.text.trim().isEmpty
          ? SimpleFileManagerSettings.defaultRootPath
          : _rootPathController.text.trim(),
      port: parsedPort ?? -1,
      bindAllInterfaces: _bindAllInterfaces,
      favoritePaths: _favoritePaths,
    );
  }

  Future<void> _addFavoritePath() async {
    final path = _favoritePathController.text.trim();
    if (path.isEmpty) {
      _showToast('请输入要收藏的文件或目录路径');
      return;
    }
    setState(() {
      _favoritePaths = <String>{..._favoritePaths, path}.toList()..sort();
      _favoritePathController.clear();
    });
    await _saveOnly();
  }

  Future<void> _removeFavoritePath(String path) async {
    setState(() {
      _favoritePaths = _favoritePaths
          .where((item) => item != path)
          .toList(growable: false);
    });
    await _saveOnly();
  }

  Future<void> _saveOnly() async {
    try {
      await _service.saveSettings(_buildSettings());
      if (mounted) {
        setState(() => _favoritePaths = _service.settings.favoritePaths);
      }
    } catch (error) {
      _showToast('保存收藏失败：$error');
    }
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    _showToast('访问地址已复制');
  }

  void _showToast(String message) {
    AppToast.show(message);
  }

  String get _stateLabel {
    switch (_state) {
      case SimpleFileManagerState.started:
        return '运行中';
      case SimpleFileManagerState.starting:
        return '启动中';
      case SimpleFileManagerState.stopping:
        return '停止中';
      case SimpleFileManagerState.stopped:
        return '已停止';
    }
  }

  Color _stateColor(ColorScheme colorScheme) {
    switch (_state) {
      case SimpleFileManagerState.started:
        return Colors.green;
      case SimpleFileManagerState.starting:
      case SimpleFileManagerState.stopping:
        return colorScheme.primary;
      case SimpleFileManagerState.stopped:
        return colorScheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('文件简易管理')),
      body: _busy && _rootPathController.text.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _enabled,
                          title: const Text('启用文件简易管理'),
                          subtitle: const Text('通过网页浏览文件树、编辑文本文件并保存修改'),
                          onChanged: _busy
                              ? null
                              : (value) {
                                  setState(() => _enabled = value);
                                  unawaited(_saveAndApply(enabled: value));
                                },
                        ),
                        const Divider(),
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _stateColor(colorScheme),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('服务状态：$_stateLabel'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (_service.localUrl != null)
                          _UrlLine(
                            label: '本机访问',
                            url: _service.localUrl!,
                            onCopy: _copyUrl,
                          ),
                        if (_service.baseUrl != null &&
                            _service.baseUrl != _service.localUrl)
                          _UrlLine(
                            label: '监听地址',
                            url: _service.baseUrl!,
                            onCopy: _copyUrl,
                          ),
                        for (final url in _service.lanUrls)
                          _UrlLine(label: '局域网访问', url: url, onCopy: _copyUrl),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _rootPathController,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            labelText: '默认文件路径',
                            hintText: SimpleFileManagerSettings.defaultRootPath,
                            prefixIcon: Icon(Icons.folder_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _portController,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '端口',
                            hintText: '12580',
                            prefixIcon: Icon(Icons.http_outlined),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _bindAllInterfaces,
                          title: const Text('允许局域网访问'),
                          subtitle: const Text(
                            '关闭后只监听 127.0.0.1，开启后电脑可访问手机 IP:端口',
                          ),
                          onChanged: _busy
                              ? null
                              : (value) =>
                                    setState(() => _bindAllInterfaces = value),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _busy
                                ? null
                                : () => unawaited(_saveAndApply()),
                            child: Text(_busy ? '保存中...' : '保存并应用'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '收藏路径',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _favoritePathController,
                                decoration: const InputDecoration(
                                  labelText: '文件或目录路径',
                                  prefixIcon: Icon(Icons.star_outline),
                                ),
                                onSubmitted: (_) =>
                                    unawaited(_addFavoritePath()),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () => unawaited(_addFavoritePath()),
                              child: const Text('添加'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_favoritePaths.isEmpty)
                          const Text('暂无收藏。网页端也可以在打开文件后收藏路径。'),
                        for (final path in _favoritePaths)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.star_rounded),
                            title: Text(
                              path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: _busy
                                  ? null
                                  : () => unawaited(_removeFavoritePath(path)),
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
              ],
            ),
    );
  }
}

class _UrlLine extends StatelessWidget {
  const _UrlLine({
    required this.label,
    required this.url,
    required this.onCopy,
  });

  final String label;
  final String url;
  final Future<void> Function(String url) onCopy;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(height: 1.1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Text('$label：', style: textStyle),
          Expanded(
            child: Text(url, style: textStyle, overflow: TextOverflow.ellipsis),
          ),
          TextButton(
            onPressed: () => unawaited(onCopy(url)),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('复制'),
          ),
        ],
      ),
    );
  }
}
