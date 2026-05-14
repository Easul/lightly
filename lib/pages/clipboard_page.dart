import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../browser/clipboard_http_server_service.dart';
import '../browser/clipboard_storage_service.dart';
import '../widgets/app_drawer.dart';

class ClipboardPage extends StatefulWidget {
  const ClipboardPage({super.key});

  @override
  State<ClipboardPage> createState() => _ClipboardPageState();
}

class _ClipboardPageState extends State<ClipboardPage>
    with WidgetsBindingObserver {
  final ClipboardStorageService _storage = ClipboardStorageService();
  final ClipboardHttpServerService _server = ClipboardHttpServerService();
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final FocusNode _textFieldFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();

  StreamSubscription<ClipboardHttpServerState>? _serverSub;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _serverEnabled = false;
  bool _isEditingClipboard = false;
  ClipboardHttpServerState _serverState = ClipboardHttpServerState.stopped;

  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  bool _canUndo = false;
  bool _canRedo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textFieldFocusNode.addListener(_handleClipboardFocusChanged);
    _listenToServerState();
    _initialize();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serverSub?.cancel();
    _controller.removeListener(_onTextChanged);
    _textFieldFocusNode.removeListener(_handleClipboardFocusChanged);
    _textFieldFocusNode.dispose();
    _editorScrollController.dispose();
    _controller.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Auto-refresh removed to prevent overwriting user edits
  }

  void _handleClipboardFocusChanged() {
    if (!mounted) return;
    setState(() {
      _isEditingClipboard = _textFieldFocusNode.hasFocus;
    });
  }

  void _onTextChanged() {
    final current = _controller.text;
    if (_undoStack.isEmpty || _undoStack.last != current) {
      _undoStack.add(current);
      if (_undoStack.length > 50) {
        _undoStack.removeAt(0);
      }
    }
    _updateUndoRedoState();
  }

  void _updateUndoRedoState() {
    final canUndo = _undoStack.length > 1;
    final canRedo = _redoStack.isNotEmpty;
    if (_canUndo != canUndo || _canRedo != canRedo) {
      setState(() {
        _canUndo = canUndo;
        _canRedo = canRedo;
      });
    }
  }

  void _undo() {
    if (_undoStack.length <= 1) return;
    final current = _undoStack.removeLast();
    _redoStack.add(current);
    final previous = _undoStack.last;
    _controller.removeListener(_onTextChanged);
    _controller.text = previous;
    _controller.addListener(_onTextChanged);
    _updateUndoRedoState();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final next = _redoStack.removeLast();
    _undoStack.add(next);
    _controller.removeListener(_onTextChanged);
    _controller.text = next;
    _controller.addListener(_onTextChanged);
    _updateUndoRedoState();
  }

  void _listenToServerState() {
    _serverSub = _server.stateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _serverState = state;
      });
    });
  }

  Future<void> _initialize() async {
    final content = await _storage.loadContent();
    final enabled = await _storage.loadServerEnabled();
    final port = await _storage.loadServerPort();
    final actuallyRunning = _server.isRunning;
    if (!mounted) return;
    setState(() {
      _controller.text = content;
      _serverEnabled = enabled && actuallyRunning;
      _serverState = actuallyRunning
          ? ClipboardHttpServerState.started
          : ClipboardHttpServerState.stopped;
      _portController.text = port?.toString() ?? '';
      _isLoading = false;
    });
    if (enabled && !actuallyRunning) {
      await _startServer();
    }
  }

  Future<void> _saveContent() async {
    final text = _controller.text;
    setState(() {
      _isSaving = true;
    });
    try {
      await _storage.saveContent(text);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已保存到剪贴板')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text != null && text.isNotEmpty) {
        final current = _controller.text;
        final newText = current.isEmpty ? text : '$current\n$text';
        _controller.text = newText;
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已从剪贴板粘贴')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('粘贴失败: $e')));
      }
    }
  }

  Future<void> _refreshFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      _controller.text = text;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已刷新系统剪贴板内容')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('刷新失败: $e')));
      }
    }
  }

  Future<void> _startServer() async {
    try {
      final portText = _portController.text.trim();
      final port = portText.isEmpty ? null : int.tryParse(portText);
      if (port != null && (port <= 0 || port > 65535)) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('端口范围应为 1-65535')));
        }
        return;
      }
      await _storage.saveServerPort(port);
      await _server.start(preferredPort: port);
      await _storage.saveServerEnabled(true);
      if (mounted) {
        setState(() {
          _serverEnabled = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('启动服务失败: $e')));
        setState(() {
          _serverEnabled = false;
        });
      }
    }
  }

  Future<void> _stopServer() async {
    await _server.stop();
    await _storage.saveServerEnabled(false);
    if (mounted) {
      setState(() {
        _serverEnabled = false;
      });
    }
  }

  Future<void> _toggleServer(bool enabled) async {
    if (enabled) {
      await _startServer();
    } else {
      await _stopServer();
    }
  }

  String get _serverStatusLabel {
    switch (_serverState) {
      case ClipboardHttpServerState.started:
        return '运行中';
      case ClipboardHttpServerState.starting:
        return '启动中...';
      case ClipboardHttpServerState.stopping:
        return '停止中...';
      case ClipboardHttpServerState.stopped:
        return '已停止';
    }
  }

  Color _serverStatusColor(ColorScheme colorScheme) {
    switch (_serverState) {
      case ClipboardHttpServerState.started:
        return colorScheme.primary;
      case ClipboardHttpServerState.starting:
      case ClipboardHttpServerState.stopping:
        return colorScheme.primary;
      case ClipboardHttpServerState.stopped:
        return colorScheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('剪贴板')),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Server status card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _serverStatusColor(colorScheme),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'HTTP 服务状态：$_serverStatusLabel',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _serverEnabled,
                            title: const Text('启用剪贴板网页服务'),
                            subtitle: const Text('通过局域网访问和编辑剪贴板内容'),
                            onChanged: _toggleServer,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _portController,
                            keyboardType: TextInputType.number,
                            enabled: !_serverEnabled,
                            decoration: const InputDecoration(
                              labelText: '服务端口（留空则随机）',
                              prefixIcon: Icon(
                                Icons.settings_ethernet_outlined,
                              ),
                            ),
                            onChanged: (_) {},
                          ),
                          if (_server.isRunning) ...[
                            const SizedBox(height: 8),
                            Text(
                              '监听地址：${_server.baseUrl ?? ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              '本机访问：${_server.localUrl ?? ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            for (final lanUrl in _server.lanUrls)
                              Text(
                                '局域网访问：$lanUrl',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Content editor
                  Text('剪贴板内容', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: Scrollbar(
                      controller: _editorScrollController,
                      thumbVisibility: true,
                      child: TextField(
                        focusNode: _textFieldFocusNode,
                        controller: _controller,
                        scrollController: _editorScrollController,
                        maxLines: null,
                        minLines: 8,
                        keyboardType: TextInputType.multiline,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: const InputDecoration(
                          hintText: '在此输入或粘贴内容...',
                          alignLabelWithHint: false,
                          contentPadding: EdgeInsets.all(12),
                        ),
                        contextMenuBuilder: _buildChineseContextMenu,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Undo/redo buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _canUndo ? _undo : null,
                          icon: const Icon(Icons.undo_outlined),
                          label: const Text('撤销'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _canRedo ? _redo : null,
                          icon: const Icon(Icons.redo_outlined),
                          label: const Text('恢复'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isSaving ? null : _saveContent,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_isSaving ? '保存中...' : '保存到剪贴板'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pasteFromClipboard,
                          icon: const Icon(Icons.content_paste_outlined),
                          label: const Text('从剪贴板粘贴'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _refreshFromClipboard,
                      icon: const Icon(Icons.refresh_outlined),
                      label: const Text('刷新（从系统剪贴板读取）'),
                    ),
                  ),
                  // Bottom safe area padding
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ],
              ),
            ),
    );
  }

  Widget _buildChineseContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: <ContextMenuButtonItem>[
        if (editableTextState.copyEnabled)
          ContextMenuButtonItem(
            onPressed: () {
              editableTextState.copySelection(SelectionChangedCause.toolbar);
            },
            label: '复制',
          ),
        if (editableTextState.cutEnabled)
          ContextMenuButtonItem(
            onPressed: () {
              editableTextState.cutSelection(SelectionChangedCause.toolbar);
            },
            label: '剪切',
          ),
        if (editableTextState.pasteEnabled)
          ContextMenuButtonItem(
            onPressed: () {
              editableTextState.pasteText(SelectionChangedCause.toolbar);
            },
            label: '粘贴',
          ),
        if (editableTextState.selectAllEnabled)
          ContextMenuButtonItem(
            onPressed: () {
              editableTextState.selectAll(SelectionChangedCause.toolbar);
            },
            label: '全选',
          ),
      ],
    );
  }
}
