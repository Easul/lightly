import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../features/ai/ai_client.dart';
import '../features/ai/ai_config.dart';
import '../features/ai/ai_conversation_context.dart';
import '../features/ai/ai_history_database.dart';
import '../features/ai/ai_settings_dialog.dart';
import '../features/ai/simple_markdown.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final AiConfigStore _configStore = AiConfigStore();
  final AiHistoryDatabase _database = AiHistoryDatabase.instance;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<String> _streamingText = ValueNotifier<String>('');

  AiConfig _config = const AiConfig();
  List<AiChatSession> _sessions = const [];
  List<AiChatMessageRecord> _messages = const [];
  AiChatSession? _session;
  http.Client? _requestClient;
  Timer? _streamScrollTimer;
  String _streamingContent = '';
  String? _generationError;
  bool _generationStopped = false;
  bool _loading = true;
  bool _sending = false;
  bool _stopping = false;
  _AiRetryRequest? _lastRetryRequest;
  int _contextOmittedCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _requestClient?.close();
    _streamScrollTimer?.cancel();
    _streamingText.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final config = await _configStore.load();
    final sessions = await _database.listSessions();
    final selected = sessions.isEmpty ? null : sessions.first;
    final messages = selected == null
        ? const <AiChatMessageRecord>[]
        : await _database.listMessages(selected.id);
    if (!mounted) return;
    setState(() {
      _config = config;
      _sessions = sessions;
      _session = selected;
      _messages = messages;
      _loading = false;
    });
    _scrollToBottom();
  }

  Future<void> _configure() async {
    final updated = await showAiSettingsDialog(context, initialConfig: _config);
    if (updated == null) return;
    await _configStore.save(updated);
    if (mounted) setState(() => _config = updated);
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    if (!_config.isReady) {
      _showMessage('请先完成 AI 接口设置');
      await _configure();
      return;
    }

    var session = _session;
    if (session == null) {
      final title = text.length > 24 ? '${text.substring(0, 24)}…' : text;
      session = await _database.createSession(title);
    }
    final userMessage = await _database.addMessage(
      sessionId: session.id,
      role: 'user',
      content: text,
    );
    _inputController.clear();
    final requestMessages = <AiMessage>[
      const AiMessage(role: 'system', content: 'You are a helpful assistant.'),
      ..._messages.map(
        (message) => AiMessage(role: message.role, content: message.content),
      ),
      AiMessage(role: 'user', content: text),
    ];

    final request = _buildRetryRequest(session.id, requestMessages);
    setState(() {
      _session = session;
      _messages = [..._messages, userMessage];
      _sending = true;
      _stopping = false;
      _generationError = null;
      _generationStopped = false;
      _lastRetryRequest = request;
      _contextOmittedCount = request.omittedMessageCount;
    });
    _streamingContent = '';
    _streamingText.value = '';
    _scrollToBottom();

    await _runGeneration(request);
  }

  Future<void> _runGeneration(_AiRetryRequest request) async {
    final session = _session;
    if (session == null || session.id != request.sessionId) return;

    final requestClient = http.Client();
    _requestClient = requestClient;
    final client = AiClient(client: requestClient);
    try {
      await for (final delta in client.streamChat(
        config: _config,
        messages: request.messages,
      )) {
        if (!mounted) return;
        _streamingContent += delta;
        _streamingText.value = _streamingContent;
        _scheduleStreamScroll();
      }
    } catch (error) {
      if (mounted && !_stopping) {
        setState(() => _generationError = _describeGenerationError(error));
      }
    } finally {
      final completedText = _streamingContent.trim();
      final stopped = _stopping;
      final completed =
          completedText.isNotEmpty && !stopped && _generationError == null;
      if (completed) {
        await _database.addMessage(
          sessionId: session.id,
          role: 'assistant',
          content: completedText,
        );
      }
      client.close();
      _requestClient = null;
      final messages = await _database.listMessages(session.id);
      final sessions = await _database.listSessions();
      if (mounted) {
        _streamScrollTimer?.cancel();
        _streamScrollTimer = null;
        setState(() {
          _messages = messages;
          _sessions = sessions;
          _sending = false;
          _stopping = false;
          _generationStopped = stopped && !completed;
        });
        if (completed) {
          _streamingContent = '';
        }
        _streamingText.value = '';
        _scrollToBottom();
      }
    }
  }

  Future<void> _retryLastResponse() async {
    final request = _lastRetryRequest;
    if (_sending || request == null) return;
    if (_session?.id != request.sessionId) {
      final sessions = await _database.listSessions();
      final session = sessions.where((item) => item.id == request.sessionId);
      if (session.isEmpty || !mounted) return;
      final messages = await _database.listMessages(request.sessionId);
      if (!mounted) return;
      setState(() {
        _session = session.first;
        _messages = messages;
      });
    }
    setState(() {
      _sending = true;
      _stopping = false;
      _generationError = null;
      _generationStopped = false;
      _contextOmittedCount = request.omittedMessageCount;
    });
    _streamingContent = '';
    _streamingText.value = '';
    await _runGeneration(request);
  }

  Future<void> _regenerateLastResponse() async {
    if (_sending || _messages.isEmpty) return;
    final last = _messages.last;
    if (last.role != 'assistant' || _session == null) return;
    await _database.deleteMessage(last.id);
    final messages = await _database.listMessages(_session!.id);
    final requestMessages = <AiMessage>[
      const AiMessage(role: 'system', content: 'You are a helpful assistant.'),
      ...messages.map(
        (message) => AiMessage(role: message.role, content: message.content),
      ),
    ];
    final request = _buildRetryRequest(_session!.id, requestMessages);
    setState(() {
      _messages = messages;
      _lastRetryRequest = request;
      _generationError = null;
      _generationStopped = false;
      _contextOmittedCount = request.omittedMessageCount;
      _stopping = false;
      _sending = true;
    });
    _streamingContent = '';
    _streamingText.value = '';
    await _runGeneration(request);
  }

  void _stop() {
    if (!_sending) return;
    setState(() => _stopping = true);
    _requestClient?.close();
  }

  String _describeGenerationError(Object error) {
    final message = error.toString();
    return message.startsWith('Bad state: ')
        ? message.substring('Bad state: '.length)
        : message;
  }

  Future<void> _selectSession(AiChatSession session) async {
    if (_sending) return;
    final messages = await _database.listMessages(session.id);
    if (!mounted) return;
    _resetGenerationPreview();
    setState(() {
      _session = session;
      _messages = messages;
    });
    _scrollToBottom();
  }

  void _newSession() {
    if (_sending) return;
    _resetGenerationPreview();
    setState(() {
      _session = null;
      _messages = const [];
    });
  }

  Future<void> _renameSession(AiChatSession session) async {
    final controller = TextEditingController(text: session.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    await _database.renameSession(session.id, title);
    final sessions = await _database.listSessions();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      if (_session?.id == session.id) {
        _session = sessions.firstWhere((item) => item.id == session.id);
      }
    });
  }

  Future<void> _deleteSession(AiChatSession session) async {
    if (_sending && _session?.id == session.id) return;
    await _database.deleteSession(session.id);
    final sessions = await _database.listSessions();
    AiChatSession? selected = _session?.id == session.id ? null : _session;
    List<AiChatMessageRecord> messages = _messages;
    if (selected == null && sessions.isNotEmpty) {
      selected = sessions.first;
      messages = await _database.listMessages(selected.id);
    } else if (selected == null) {
      messages = const [];
    }
    if (!mounted) return;
    if (selected?.id != _session?.id) _resetGenerationPreview();
    setState(() {
      _sessions = sessions;
      _session = selected;
      _messages = messages;
    });
  }

  Future<void> _editMessage(
    AiChatMessageRecord message, {
    bool resend = false,
  }) async {
    if (_sending) return;
    final controller = TextEditingController(text: message.content);
    final content = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑消息'),
        content: TextField(controller: controller, minLines: 3, maxLines: 10),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (content == null || content.isEmpty) return;
    await _database.updateMessage(message.id, content);
    if (resend) {
      await _database.deleteMessagesAfter(
        sessionId: message.sessionId,
        messageId: message.id,
      );
      final messages = await _database.listMessages(message.sessionId);
      final requestMessages = <AiMessage>[
        const AiMessage(
          role: 'system',
          content: 'You are a helpful assistant.',
        ),
        ...messages.map(
          (item) => AiMessage(role: item.role, content: item.content),
        ),
      ];
      final request = _buildRetryRequest(message.sessionId, requestMessages);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _lastRetryRequest = request;
        _generationError = null;
        _generationStopped = false;
        _contextOmittedCount = request.omittedMessageCount;
        _sending = true;
      });
      _streamingContent = '';
      _streamingText.value = '';
      await _runGeneration(request);
      return;
    }
    await _reloadMessages();
  }

  Future<void> _deleteMessage(AiChatMessageRecord message) async {
    if (_sending) return;
    await _database.deleteMessage(message.id);
    await _reloadMessages();
  }

  Future<void> _reloadMessages() async {
    final session = _session;
    if (session == null) return;
    final messages = await _database.listMessages(session.id);
    if (mounted) setState(() => _messages = messages);
  }

  void _resetGenerationPreview() {
    _streamingContent = '';
    _streamingText.value = '';
    _generationError = null;
    _generationStopped = false;
    _lastRetryRequest = null;
    _contextOmittedCount = 0;
  }

  _AiRetryRequest _buildRetryRequest(
    int sessionId,
    Iterable<AiMessage> messages,
  ) {
    final context = AiConversationContext.build(messages);
    return _AiRetryRequest(
      sessionId: sessionId,
      messages: List<AiMessage>.unmodifiable(context.messages),
      omittedMessageCount: context.omittedMessageCount,
    );
  }

  Future<void> _showSessions() async {
    final searchController = TextEditingController();
    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final normalizedQuery = query.trim().toLowerCase();
          final sessions = normalizedQuery.isEmpty
              ? _sessions
              : _sessions
                    .where(
                      (session) =>
                          session.title.toLowerCase().contains(normalizedQuery),
                    )
                    .toList(growable: false);
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.76,
              child: Column(
                children: [
                  ListTile(
                    title: const Text('历史对话'),
                    trailing: IconButton(
                      tooltip: '新对话',
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _newSession();
                      },
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TextField(
                      controller: searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: '搜索对话标题',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清除搜索',
                                onPressed: () {
                                  searchController.clear();
                                  setSheetState(() => query = '');
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                      onChanged: (value) => setSheetState(() => query = value),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: sessions.isEmpty
                        ? Center(
                            child: Text(
                              normalizedQuery.isEmpty ? '暂无历史对话' : '没有匹配的对话',
                            ),
                          )
                        : ListView.builder(
                            itemCount: sessions.length,
                            itemBuilder: (context, index) {
                              final session = sessions[index];
                              return ListTile(
                                dense: true,
                                visualDensity: const VisualDensity(
                                  vertical: -2,
                                ),
                                selected: session.id == _session?.id,
                                title: Text(
                                  session.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  _formatSessionTime(session.updatedAt),
                                  maxLines: 1,
                                ),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  unawaited(_selectSession(session));
                                },
                                trailing: PopupMenuButton<String>(
                                  onSelected: (action) {
                                    if (action == 'rename') {
                                      unawaited(_renameSession(session));
                                    } else {
                                      unawaited(_deleteSession(session));
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'rename',
                                      child: Text('重命名'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('删除'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    searchController.dispose();
    if (mounted) setState(() {});
  }

  String _formatSessionTime(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  void _showMessageActions(AiChatMessageRecord message) {
    final isLastMessage =
        _messages.isNotEmpty && _messages.last.id == message.id;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制'),
              onTap: () {
                Navigator.pop(context);
                unawaited(
                  Clipboard.setData(ClipboardData(text: message.content)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(
                isLastMessage && message.role == 'user' ? '编辑并重发' : '编辑',
              ),
              onTap: () {
                Navigator.pop(context);
                unawaited(
                  _editMessage(
                    message,
                    resend: isLastMessage && message.role == 'user',
                  ),
                );
              },
            ),
            if (isLastMessage && message.role == 'assistant')
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('重新生成'),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_regenerateLastResponse());
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('删除'),
              onTap: () {
                Navigator.pop(context);
                unawaited(_deleteMessage(message));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _scheduleStreamScroll() {
    if (_streamScrollTimer?.isActive ?? false) return;
    _streamScrollTimer = Timer(const Duration(milliseconds: 80), () {
      _streamScrollTimer = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openMarkdownLink(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      _showMessage('链接格式无效');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开链接'),
        content: Text(
          '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('打开'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!await launchUrl(uri)) _showMessage('无法打开该链接');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_session?.title ?? '聊天工具'),
        actions: [
          IconButton(
            tooltip: '新对话',
            onPressed: _sending ? null : _newSession,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: '历史对话',
            onPressed: _showSessions,
            icon: const Icon(Icons.history_rounded),
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
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty && !_sending
                      ? Center(
                          child: Text(
                            _config.isReady ? '输入消息开始对话' : '请先设置 AI 接口',
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount:
                              _messages.length +
                              ((_sending ||
                                      _streamingContent.isNotEmpty ||
                                      _generationError != null ||
                                      _generationStopped)
                                  ? 1
                                  : 0),
                          itemBuilder: (context, index) {
                            if (index == _messages.length) {
                              if (_sending) {
                                return ValueListenableBuilder<String>(
                                  valueListenable: _streamingText,
                                  builder: (context, content, child) =>
                                      _ChatBubble(
                                        role: 'assistant',
                                        content: content,
                                        streaming: true,
                                        onLinkTap: _openMarkdownLink,
                                      ),
                                );
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_streamingContent.trim().isNotEmpty)
                                    _ChatBubble(
                                      role: 'assistant',
                                      content: _streamingContent,
                                      onLinkTap: _openMarkdownLink,
                                    ),
                                  if (_generationError != null ||
                                      _generationStopped)
                                    _GenerationStatus(
                                      error: _generationError,
                                      onRetry: _retryLastResponse,
                                    ),
                                ],
                              );
                            }
                            final message = _messages[index];
                            return _ChatBubble(
                              role: message.role,
                              content: message.content,
                              onLongPress: () => _showMessageActions(message),
                              onLinkTap: _openMarkdownLink,
                              onCopy: () => unawaited(
                                Clipboard.setData(
                                  ClipboardData(text: message.content),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (_contextOmittedCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '本次请求已省略较早的 $_contextOmittedCount 条消息，以控制上下文长度',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _inputController,
                            minLines: 1,
                            maxLines: 6,
                            enabled: !_sending,
                            textInputAction: TextInputAction.send,
                            onSubmitted: _sending
                                ? null
                                : (_) => unawaited(_send()),
                            decoration: const InputDecoration(
                              hintText: '输入消息…',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: _sending ? '停止' : '发送',
                          onPressed: _sending ? _stop : _send,
                          icon: Icon(
                            _sending ? Icons.stop_rounded : Icons.send_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.role,
    required this.content,
    this.streaming = false,
    this.onLongPress,
    this.onCopy,
    this.onLinkTap,
  });

  final String role;
  final String content;
  final bool streaming;
  final VoidCallback? onLongPress;
  final VoidCallback? onCopy;
  final ValueChanged<String>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 9),
          decoration: BoxDecoration(
            color: isUser
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: isUser
                    ? SelectableText(content)
                    : SimpleMarkdown(
                        streaming ? '$content▍' : content,
                        onLinkTap: onLinkTap,
                      ),
              ),
              if (onCopy != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '复制',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded, size: 17),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenerationStatus extends StatelessWidget {
  const _GenerationStatus({required this.error, required this.onRetry});

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stopped = error == null;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2, bottom: 8),
      child: Row(
        children: [
          Icon(
            stopped ? Icons.pause_circle_outline : Icons.error_outline,
            size: 18,
            color: stopped ? colorScheme.onSurfaceVariant : colorScheme.error,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              stopped ? '已停止生成' : '生成失败：$error',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: stopped
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.error,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('重试'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiRetryRequest {
  const _AiRetryRequest({
    required this.sessionId,
    required this.messages,
    required this.omittedMessageCount,
  });

  final int sessionId;
  final List<AiMessage> messages;
  final int omittedMessageCount;
}
