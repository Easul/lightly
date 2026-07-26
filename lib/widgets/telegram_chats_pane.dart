import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/telegram_chat_page.dart';
import '../services/app_toast.dart';
import '../features/telegram/telegram_checkin_models.dart';
import '../features/telegram/telegram_tdlib_service.dart';

class TelegramChatsPane extends StatefulWidget {
  const TelegramChatsPane({super.key});

  @override
  State<TelegramChatsPane> createState() => _TelegramChatsPaneState();
}

class _TelegramChatsPaneState extends State<TelegramChatsPane> {
  final TelegramTdlibService _telegram = TelegramTdlibService.instance;
  final TextEditingController _searchController = TextEditingController();
  List<TelegramChatSummary> _chats = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _telegram.authStep.addListener(_handleAuthChanged);
    if (_telegram.authStep.value == TelegramAuthStep.ready) {
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _telegram.authStep.removeListener(_handleAuthChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleAuthChanged() {
    if (!mounted) return;
    setState(() {});
    if (_telegram.authStep.value == TelegramAuthStep.ready && _chats.isEmpty) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final chats = await _telegram.loadChats();
      if (mounted) setState(() => _chats = chats);
    } catch (error) {
      _toast('加载会话失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openUsername() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() => _loading = true);
    try {
      final chat = await _telegram.resolvePublicChat(query);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => TelegramChatPage(chat: chat)),
      );
      await _refresh();
    } catch (error) {
      _toast('查找会话失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openChat(TelegramChatSummary chat) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => TelegramChatPage(chat: chat)),
    );
    await _refresh();
  }

  void _toast(String message) => unawaited(AppToast.show(message));

  @override
  Widget build(BuildContext context) {
    if (_telegram.authStep.value != TelegramAuthStep.ready) {
      return const Center(child: Text('登录 Telegram 后可查看最近会话'));
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: '输入 @username 打开会话',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _openUsername(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _loading ? null : _openUsername,
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading && _chats.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (_chats.isEmpty)
            Center(
              child: TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('加载最近会话'),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var index = 0; index < _chats.length; index++) ...[
                    _ChatTile(chat: _chats[index], onTap: _openChat),
                    if (index != _chats.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat, required this.onTap});

  final TelegramChatSummary chat;
  final ValueChanged<TelegramChatSummary> onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => onTap(chat),
      leading: CircleAvatar(
        child: Text(chat.title.isEmpty ? '?' : chat.title.characters.first),
      ),
      title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        chat.lastMessage.isEmpty ? '暂无消息' : chat.lastMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: chat.unreadCount > 0
          ? Badge(label: Text('${chat.unreadCount}'))
          : const Icon(Icons.chevron_right_rounded),
    );
  }
}
