import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_toast.dart';
import '../telegram_checkin/telegram_checkin_models.dart';
import '../telegram_checkin/telegram_tdlib_service.dart';

class TelegramChatPage extends StatefulWidget {
  const TelegramChatPage({super.key, required this.chat});

  final TelegramChatSummary chat;

  @override
  State<TelegramChatPage> createState() => _TelegramChatPageState();
}

class _TelegramChatPageState extends State<TelegramChatPage> {
  final TelegramTdlibService _telegram = TelegramTdlibService.instance;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<TelegramMessagePreview> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    unawaited(_closeChatSafely());
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final messages = await _telegram.loadChatMessages(widget.chat.id);
      if (mounted) {
        setState(() => _messages = messages.reversed.toList());
        _scrollToLatest();
      }
    } catch (error) {
      _toast('加载消息失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _messages.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final older = await _telegram.loadChatMessages(
        widget.chat.id,
        fromMessageId: _messages.first.id,
      );
      final knownIds = _messages.map((message) => message.id).toSet();
      final uniqueOlder = older
          .where((message) => !knownIds.contains(message.id))
          .toList()
          .reversed;
      if (mounted) {
        final oldMaxScrollExtent = _scrollController.hasClients
            ? _scrollController.position.maxScrollExtent
            : 0.0;
        final oldOffset = _scrollController.hasClients
            ? _scrollController.offset
            : 0.0;
        setState(() => _messages = [...uniqueOlder, ..._messages]);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          final addedExtent =
              _scrollController.position.maxScrollExtent - oldMaxScrollExtent;
          _scrollController.jumpTo(
            (oldOffset + addedExtent).clamp(
              0.0,
              _scrollController.position.maxScrollExtent,
            ),
          );
        });
      }
    } catch (error) {
      _toast('加载更早消息失败：$error');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _telegram.sendText(widget.chat.id, text);
      _inputController.clear();
      await _refresh();
    } catch (error) {
      _toast('发送失败：$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String message) => unawaited(AppToast.show(message));

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _closeChatSafely() async {
    try {
      await _telegram.closeChat(widget.chat.id);
    } catch (error) {
      debugPrint('Close Telegram chat failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chat.title),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Center(
                          child: TextButton(
                            onPressed: _loadingMore ? null : _loadMore,
                            child: Text(_loadingMore ? '加载中…' : '加载更早消息'),
                          ),
                        );
                      }
                      return _MessageBubble(message: _messages[index - 1]);
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: '输入消息',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final TelegramMessagePreview message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: message.isOutgoing
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
        decoration: BoxDecoration(
          color: message.isOutgoing
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(message.text),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.date),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
