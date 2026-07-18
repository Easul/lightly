import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../browser/clipboard_http_server_service.dart';
import '../browser/clipboard_storage_service.dart';
import '../services/app_toast.dart';
import 'clipboard_page_sections.dart';

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
  ClipboardHttpServerState _serverState = ClipboardHttpServerState.stopped;

  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  bool _canUndo = false;
  bool _canRedo = false;

  void _showToast(String message) {
    unawaited(AppToast.show(message));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToServerState();
    _initialize();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serverSub?.cancel();
    _controller.removeListener(_onTextChanged);
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
        _showToast('已保存到网页剪贴板');
      }
    } catch (e) {
      if (mounted) {
        _showToast('保存失败: $e');
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
          _showToast('已从剪贴板粘贴');
        }
      }
    } catch (e) {
      if (mounted) {
        _showToast('粘贴失败: $e');
      }
    }
  }

  Future<void> _refreshSavedContent() async {
    try {
      final text = await _storage.loadContent();
      _controller.text = text;
      if (mounted) {
        _showToast('已刷新网页保存内容');
      }
    } catch (e) {
      if (mounted) {
        _showToast('刷新失败: $e');
      }
    }
  }

  Future<void> _startServer() async {
    try {
      final portText = _portController.text.trim();
      final port = portText.isEmpty ? null : int.tryParse(portText);
      if (port != null && (port <= 0 || port > 65535)) {
        if (mounted) {
          _showToast('端口范围应为 1-65535');
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
        _showToast('启动服务失败: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('剪贴板')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipboardServerStatusCard(
                    server: _server,
                    serverEnabled: _serverEnabled,
                    serverState: _serverState,
                    portController: _portController,
                    onToggleServer: (enabled) =>
                        unawaited(_toggleServer(enabled)),
                  ),
                  const SizedBox(height: 16),
                  ClipboardEditorSection(
                    controller: _controller,
                    focusNode: _textFieldFocusNode,
                    scrollController: _editorScrollController,
                    contextMenuBuilder: _buildChineseContextMenu,
                  ),
                  const SizedBox(height: 16),
                  ClipboardUndoRedoRow(
                    canUndo: _canUndo,
                    canRedo: _canRedo,
                    onUndo: _undo,
                    onRedo: _redo,
                  ),
                  const SizedBox(height: 16),
                  ClipboardActionButtons(
                    isSaving: _isSaving,
                    onSave: () => unawaited(_saveContent()),
                    onPaste: () => unawaited(_pasteFromClipboard()),
                    onRefresh: () => unawaited(_refreshSavedContent()),
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
