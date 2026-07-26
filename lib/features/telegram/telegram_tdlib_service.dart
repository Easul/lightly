import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tdlib/td_api.dart' as td;
import 'package:tdlib/tdlib.dart';

import '../../core/network/local_proxy_endpoint_provider.dart';
import 'telegram_checkin_models.dart';

enum TelegramAuthStep {
  loading,
  phone,
  code,
  password,
  ready,
  loggedOut,
  error,
}

class TelegramTdlibService {
  TelegramTdlibService._();

  static final TelegramTdlibService instance = TelegramTdlibService._();

  final ValueNotifier<TelegramAuthStep> authStep =
      ValueNotifier<TelegramAuthStep>(TelegramAuthStep.loading);
  final ValueNotifier<String> proxyStatus = ValueNotifier<String>('正在检查代理');
  final Map<String, Completer<td.TdObject>> _requests =
      <String, Completer<td.TdObject>>{};
  Timer? _receiveTimer;
  Future<void> _authorizationQueue = Future<void>.value();
  int _clientId = 0;
  int _requestId = 0;
  int? _configuredProxyPort;
  TelegramCheckinConfig? _config;

  /// Source of the local SOCKS5 port. Injected by the composition root so this
  /// feature does not depend on a concrete proxy implementation. Defaults to a
  /// null provider (direct connection) until wired.
  LocalProxyEndpointProvider proxyEndpointProvider =
      const _NullProxyEndpointProvider();

  Future<void> start(TelegramCheckinConfig config) async {
    _config = config;
    if (_clientId == 0) {
      _clientId = tdCreate();
      _receiveTimer ??= Timer.periodic(
        const Duration(milliseconds: 80),
        (_) => _drainUpdates(),
      );
    }
    authStep.value = TelegramAuthStep.loading;
    final state = await _request(const td.GetAuthorizationState());
    if (state is td.AuthorizationState) {
      await _enqueueAuthorizationState(state);
    }
  }

  Future<void> submitPhone(String phoneNumber) async {
    await configureProxyIfAvailable();
    await _expectOk(
      td.SetAuthenticationPhoneNumber(phoneNumber: phoneNumber, settings: null),
    );
  }

  Future<void> submitCode(String code) async {
    await _expectOk(td.CheckAuthenticationCode(code: code));
  }

  Future<void> submitPassword(String password) async {
    await _expectOk(td.CheckAuthenticationPassword(password: password));
  }

  Future<List<TelegramMessagePreview>> fetchLatest(String rawUsername) async {
    await configureProxyIfAvailable();
    _ensureReady();
    final chat = await _resolveChat(rawUsername);
    final response = await _request(
      td.GetChatHistory(
        chatId: chat.id,
        fromMessageId: 0,
        offset: 0,
        limit: 10,
        onlyLocal: false,
      ),
    );
    if (response is td.TdError) throw StateError(response.message);
    final messages = response as td.Messages;
    return messages.messages
        .map((message) {
          final content = message.content;
          final text = content is td.MessageText
              ? content.text.text
              : '[${content.getConstructor()}]';
          return TelegramMessagePreview(
            id: message.id,
            text: text,
            date: DateTime.fromMillisecondsSinceEpoch(message.date * 1000),
            isOutgoing: message.isOutgoing,
          );
        })
        .toList(growable: false);
  }

  Future<void> sendCommand(String rawUsername, String command) async {
    await configureProxyIfAvailable();
    _ensureReady();
    final chat = await _resolveChat(rawUsername);
    final response = await _request(
      td.SendMessage(
        chatId: chat.id,
        messageThreadId: 0,
        inputMessageContent: td.InputMessageText(
          text: td.FormattedText(text: command, entities: const []),
          disableWebPagePreview: true,
          clearDraft: true,
        ),
      ),
    );
    if (response is td.TdError) throw StateError(response.message);
  }

  Future<List<TelegramChatSummary>> loadChats({int limit = 30}) async {
    await configureProxyIfAvailable();
    _ensureReady();
    final loadResponse = await _request(
      td.LoadChats(chatList: null, limit: limit),
    );
    if (loadResponse is td.TdError && loadResponse.code != 404) {
      throw StateError(loadResponse.message);
    }
    final response = await _request(td.GetChats(chatList: null, limit: limit));
    if (response is td.TdError) throw StateError(response.message);
    final chats = response as td.Chats;
    final summaries = await Future.wait(
      chats.chatIds.map((chatId) async {
        final chatResponse = await _request(td.GetChat(chatId: chatId));
        if (chatResponse is td.TdError) return null;
        return _toChatSummary(chatResponse as td.Chat);
      }),
    );
    return summaries.whereType<TelegramChatSummary>().toList(growable: false);
  }

  Future<TelegramChatSummary> resolvePublicChat(String rawUsername) async {
    await configureProxyIfAvailable();
    _ensureReady();
    return _toChatSummary(await _resolveChat(rawUsername));
  }

  Future<List<TelegramMessagePreview>> loadChatMessages(
    int chatId, {
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    await configureProxyIfAvailable();
    _ensureReady();
    final isLatestPage = fromMessageId == 0;
    if (isLatestPage) {
      await _expectOk(td.OpenChat(chatId: chatId));
    }
    final response = await _request(
      td.GetChatHistory(
        chatId: chatId,
        fromMessageId: fromMessageId,
        offset: 0,
        limit: limit,
        onlyLocal: false,
      ),
    );
    if (response is td.TdError) throw StateError(response.message);
    final messages = (response as td.Messages).messages;
    if (isLatestPage && messages.isNotEmpty) {
      await _expectOk(
        td.ViewMessages(
          chatId: chatId,
          messageIds: messages.map((message) => message.id).toList(),
          source: null,
          forceRead: true,
        ),
      );
    }
    return messages.map(_toMessagePreview).toList(growable: false);
  }

  Future<void> closeChat(int chatId) async {
    if (_clientId == 0) return;
    await _expectOk(td.CloseChat(chatId: chatId));
  }

  Future<void> sendText(int chatId, String text) async {
    await configureProxyIfAvailable();
    _ensureReady();
    final response = await _request(
      td.SendMessage(
        chatId: chatId,
        messageThreadId: 0,
        inputMessageContent: td.InputMessageText(
          text: td.FormattedText(text: text, entities: const []),
          disableWebPagePreview: false,
          clearDraft: true,
        ),
      ),
    );
    if (response is td.TdError) throw StateError(response.message);
  }

  Future<void> logout() async {
    await configureProxyIfAvailable();
    _ensureReady();
    await _expectOk(const td.LogOut());
    authStep.value = TelegramAuthStep.loading;
  }

  TelegramChatSummary _toChatSummary(td.Chat chat) {
    final lastMessage = chat.lastMessage;
    return TelegramChatSummary(
      id: chat.id,
      title: chat.title,
      lastMessage: lastMessage == null ? '' : _messageText(lastMessage.content),
      date: lastMessage == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastMessage.date * 1000),
      unreadCount: chat.unreadCount,
    );
  }

  TelegramMessagePreview _toMessagePreview(td.Message message) {
    return TelegramMessagePreview(
      id: message.id,
      text: _messageText(message.content),
      date: DateTime.fromMillisecondsSinceEpoch(message.date * 1000),
      isOutgoing: message.isOutgoing,
    );
  }

  String _messageText(td.MessageContent content) {
    return content is td.MessageText
        ? content.text.text
        : '[${content.getConstructor()}]';
  }

  Future<td.Chat> _resolveChat(String rawUsername) async {
    final username = rawUsername.trim().replaceFirst(RegExp(r'^@'), '');
    final response = await _request(td.SearchPublicChat(username: username));
    if (response is td.TdError) throw StateError(response.message);
    return response as td.Chat;
  }

  Future<void> configureProxyIfAvailable() async {
    if (_clientId == 0) return;
    final port = proxyEndpointProvider.localSocks5Port;
    if (port == null) {
      proxyStatus.value = '本地代理未运行，TDLib 将尝试直连';
      return;
    }
    if (_configuredProxyPort == port) {
      proxyStatus.value = '已使用本地代理 127.0.0.1:$port';
      return;
    }
    final response = await _request(
      td.AddProxy(
        server: '127.0.0.1',
        port: port,
        enable: true,
        type: const td.ProxyTypeSocks5(username: '', password: ''),
      ),
    );
    if (response is td.TdError) {
      proxyStatus.value = '代理启用失败：${response.message}';
      throw StateError(response.message);
    }
    _configuredProxyPort = port;
    proxyStatus.value = '已使用本地代理 127.0.0.1:$port';
  }

  Future<void> _handleAuthorizationState(td.AuthorizationState state) async {
    if (state is td.AuthorizationStateWaitTdlibParameters) {
      final config = _config;
      if (config == null || !config.hasApiCredentials) {
        authStep.value = TelegramAuthStep.error;
        return;
      }
      final directory = await getApplicationSupportDirectory();
      final databaseDirectory = Directory('${directory.path}/telegram');
      await databaseDirectory.create(recursive: true);
      await _expectOk(
        td.SetTdlibParameters(
          useTestDc: false,
          databaseDirectory: databaseDirectory.path,
          filesDirectory: databaseDirectory.path,
          databaseEncryptionKey: '',
          useFileDatabase: false,
          useChatInfoDatabase: true,
          useMessageDatabase: true,
          useSecretChats: false,
          apiId: config.apiId,
          apiHash: config.apiHash,
          systemLanguageCode: 'zh-Hans',
          deviceModel: 'Android',
          systemVersion: Platform.operatingSystemVersion,
          applicationVersion: '1.0.1',
          enableStorageOptimizer: true,
          ignoreFileNames: true,
        ),
      );
      await configureProxyIfAvailable();
    } else if (state is td.AuthorizationStateWaitPhoneNumber) {
      await configureProxyIfAvailable();
      authStep.value = TelegramAuthStep.phone;
    } else if (state is td.AuthorizationStateWaitCode) {
      await configureProxyIfAvailable();
      authStep.value = TelegramAuthStep.code;
    } else if (state is td.AuthorizationStateWaitPassword) {
      await configureProxyIfAvailable();
      authStep.value = TelegramAuthStep.password;
    } else if (state is td.AuthorizationStateReady) {
      await configureProxyIfAvailable();
      authStep.value = TelegramAuthStep.ready;
    } else if (state is td.AuthorizationStateClosed) {
      _clientId = 0;
      _configuredProxyPort = null;
      _failPendingRequests(StateError('Telegram 连接已关闭'));
      authStep.value = TelegramAuthStep.loggedOut;
    }
  }

  Future<void> _enqueueAuthorizationState(td.AuthorizationState state) {
    _authorizationQueue = _authorizationQueue
        .then((_) => _handleAuthorizationState(state))
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('Telegram authorization update failed: $error');
          authStep.value = TelegramAuthStep.error;
        });
    return _authorizationQueue;
  }

  void _drainUpdates() {
    for (var index = 0; index < 20; index++) {
      final object = tdReceive(0);
      if (object == null) return;
      final clientId = object.clientId;
      if (clientId != null && clientId != _clientId) continue;
      final extra = object.extra?.toString();
      if (extra != null) {
        _requests.remove(extra)?.complete(object);
      }
      if (object is td.UpdateAuthorizationState) {
        unawaited(_enqueueAuthorizationState(object.authorizationState));
      }
    }
  }

  Future<td.TdObject> _request(td.TdFunction function) {
    if (_clientId == 0) {
      throw StateError('Telegram 客户端尚未启动');
    }
    final extra = 'tg_${_requestId++}';
    final completer = Completer<td.TdObject>();
    _requests[extra] = completer;
    try {
      tdSend(_clientId, function, extra);
    } catch (_) {
      _requests.remove(extra);
      rethrow;
    }
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        if (identical(_requests[extra], completer)) {
          _requests.remove(extra);
        }
        throw TimeoutException('Telegram 请求超时：${function.getConstructor()}');
      },
    );
  }

  void _failPendingRequests(Object error) {
    final requests = _requests.values.toList(growable: false);
    _requests.clear();
    for (final request in requests) {
      if (!request.isCompleted) request.completeError(error);
    }
  }

  Future<void> _expectOk(td.TdFunction function) async {
    final response = await _request(function);
    if (response is td.TdError) throw StateError(response.message);
  }

  void _ensureReady() {
    if (authStep.value != TelegramAuthStep.ready) {
      throw StateError('Telegram 账号尚未登录');
    }
  }
}

/// Default provider used before the composition root injects a real one.
/// Reports no local proxy, so TDLib falls back to a direct connection —
/// identical to the previous behavior when the proxy was not running.
class _NullProxyEndpointProvider implements LocalProxyEndpointProvider {
  const _NullProxyEndpointProvider();

  @override
  int? get localSocks5Port => null;
}
