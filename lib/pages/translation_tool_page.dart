import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/ai/ai_client.dart';
import '../features/ai/ai_config.dart';
import '../features/ai/ai_settings_dialog.dart';
import '../features/ai/translation_history.dart';
import '../services/app_toast.dart';
import '../services/translation_overlay_service.dart';

class TranslationToolPage extends StatefulWidget {
  const TranslationToolPage({super.key});

  @override
  State<TranslationToolPage> createState() => _TranslationToolPageState();
}

class _TranslationToolPageState extends State<TranslationToolPage>
    with WidgetsBindingObserver {
  static const List<String> _languages = <String>['自动', '中文', '英文', '日文', '韩文'];

  final AiConfigStore _configStore = AiConfigStore();
  final TranslationHistoryStore _historyStore = TranslationHistoryStore();
  final TranslationOverlayService _overlayService = TranslationOverlayService();
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _outputController = TextEditingController();

  AiConfig _config = const AiConfig();
  List<TranslationHistoryEntry> _history = const [];
  String _targetLanguage = '自动';
  bool _loading = true;
  bool _translating = false;
  bool _overlayRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inputController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshOverlayState());
  }

  Future<void> _initialize() async {
    final results = await Future.wait<dynamic>([
      _configStore.load(),
      _historyStore.list(),
      _overlayService.isRunning(),
    ]);
    if (!mounted) return;
    setState(() {
      _config = results[0] as AiConfig;
      _history = results[1] as List<TranslationHistoryEntry>;
      _overlayRunning = results[2] as bool;
      _loading = false;
    });
  }

  Future<void> _refreshHistory() async {
    final history = await _historyStore.list();
    if (mounted) setState(() => _history = history);
  }

  Future<void> _refreshOverlayState() async {
    final running = await _overlayService.isRunning();
    if (mounted && running != _overlayRunning) {
      setState(() => _overlayRunning = running);
    }
    await _refreshHistory();
  }

  Future<void> _configure() async {
    final updated = await showAiSettingsDialog(context, initialConfig: _config);
    if (updated == null) return;
    await _configStore.save(updated);
    if (_overlayRunning) await _overlayService.show(updated);
    if (mounted) setState(() => _config = updated);
  }

  Future<void> _translate() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _translating) return;
    if (!_config.isReady) {
      _showMessage('请先完成 AI 接口设置');
      await _configure();
      return;
    }
    setState(() => _translating = true);
    final client = AiClient();
    try {
      final translated = await client.translate(
        config: _config,
        text: text,
        targetLanguage: _targetLanguage,
      );
      final entry = TranslationHistoryEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        source: text,
        translation: translated,
        targetLanguage: _targetLanguage,
        createdAt: DateTime.now(),
      );
      await _historyStore.save(entry);
      if (!mounted) return;
      _outputController.text = translated;
      await _refreshHistory();
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      client.close();
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _toggleOverlay() async {
    try {
      if (_overlayRunning) {
        await _overlayService.close();
      } else {
        if (!_config.isReady) {
          _showMessage('请先完成 AI 接口设置');
          await _configure();
          if (!_config.isReady) return;
        }
        if (!await _overlayService.hasPermission()) {
          await _overlayService.requestPermission();
          _showMessage('请允许显示在其他应用上层，然后返回再次开启');
          return;
        }
        await _overlayService.show(_config);
      }
      await Future<void>.delayed(const Duration(milliseconds: 160));
      await _refreshOverlayState();
    } catch (error) {
      if (mounted) _showMessage('悬浮翻译操作失败：$error');
    }
  }

  Future<void> _editEntry(TranslationHistoryEntry entry) async {
    final sourceController = TextEditingController(text: entry.source);
    final translationController = TextEditingController(
      text: entry.translation,
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑翻译记录'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: sourceController,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '原文'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: translationController,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '译文'),
              ),
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
    if (saved == true) {
      await _historyStore.update(
        TranslationHistoryEntry(
          id: entry.id,
          source: sourceController.text.trim(),
          translation: translationController.text.trim(),
          targetLanguage: entry.targetLanguage,
          createdAt: entry.createdAt,
        ),
      );
      await _refreshHistory();
    }
    sourceController.dispose();
    translationController.dispose();
  }

  Future<void> _deleteEntry(String id) async {
    await _historyStore.delete(id);
    await _refreshHistory();
  }

  Future<void> _clearHistory() async {
    await _historyStore.clear();
    await _refreshHistory();
  }

  void _useEntry(TranslationHistoryEntry entry) {
    _inputController.text = entry.source;
    _outputController.text = entry.translation;
    setState(() => _targetLanguage = entry.targetLanguage);
  }

  void _showMessage(String message) {
    unawaited(AppToast.show(message));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('翻译工具'),
        actions: [
          IconButton(
            tooltip: _overlayRunning ? '关闭悬浮翻译' : '开启悬浮翻译',
            onPressed: _toggleOverlay,
            icon: Icon(
              _overlayRunning
                  ? Icons.picture_in_picture_alt_rounded
                  : Icons.picture_in_picture_outlined,
            ),
          ),
          IconButton(
            tooltip: '接口设置',
            onPressed: _configure,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _targetLanguage,
                  decoration: const InputDecoration(labelText: '翻译为'),
                  items: _languages
                      .map(
                        (language) => DropdownMenuItem(
                          value: language,
                          child: Text(language),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _targetLanguage = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _inputController,
                  minLines: 5,
                  maxLines: 10,
                  decoration: InputDecoration(
                    labelText: '原文',
                    alignLabelWithHint: true,
                    suffixIcon: IconButton(
                      tooltip: '清空',
                      onPressed: _inputController.clear,
                      icon: const Icon(Icons.clear_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _translating ? null : _translate,
                  icon: _translating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.translate_rounded),
                  label: Text(_translating ? '翻译中…' : '翻译'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _outputController,
                  readOnly: true,
                  minLines: 5,
                  maxLines: 10,
                  decoration: InputDecoration(
                    labelText: '译文',
                    alignLabelWithHint: true,
                    suffixIcon: IconButton(
                      tooltip: '复制译文',
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _outputController.text),
                        );
                        if (mounted) _showMessage('已复制');
                      },
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Text(
                      '历史记录',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _history.isEmpty ? null : _clearHistory,
                      child: const Text('清空'),
                    ),
                  ],
                ),
                if (_history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: Text('暂无翻译记录')),
                  )
                else
                  ..._history.map(
                    (entry) => Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        onTap: () => _useEntry(entry),
                        title: Text(
                          entry.source,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          entry.translation,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) {
                            switch (action) {
                              case 'copy':
                                unawaited(
                                  Clipboard.setData(
                                    ClipboardData(text: entry.translation),
                                  ),
                                );
                              case 'edit':
                                unawaited(_editEntry(entry));
                              case 'delete':
                                unawaited(_deleteEntry(entry.id));
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'copy', child: Text('复制译文')),
                            PopupMenuItem(value: 'edit', child: Text('编辑')),
                            PopupMenuItem(value: 'delete', child: Text('删除')),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
