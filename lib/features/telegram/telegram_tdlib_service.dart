import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/network/local_proxy_endpoint_provider.dart';
import 'telegram_checkin_models.dart';
import 'telegram_plugin_platform_gateway.dart';
import 'telegram_td_json_codec.dart';

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
  final Map<String, Completer<TelegramJson>> _requests =
      <String, Completer<TelegramJson>>{};
  final TelegramPluginPlatformGateway _plugin =
      TelegramPluginPlatformGateway.instance;
  final TelegramTdJsonCodec _codec = const TelegramTdJsonCodec();
  StreamSubscription<String>? _resultSubscription;
  StreamSubscription<void>? _disconnectSubscription;
  Future<void> _authorizationQueue = Future<void>.value();
  int _clientId = 0;
  int _requestId = 0;
  int? _configuredProxyPort;
  TelegramCheckinConfig? _config;

  LocalProxyEndpointProvider proxyEndpointProvider =
      const _NullProxyEndpointProvider();

  Future<void> start(TelegramCheckinConfig config) async {
    _config = config;
    if (_clientId == 0) {
      if (!await _plugin.connect()) {
        throw StateError('Telegram 插件未安装、签名不匹配或版本不兼容');
      }
      _resultSubscription ??= _plugin.results.listen(_handleRawResult);
      _disconnectSubscription ??= _plugin.disconnects.listen((_) {
        _clientId = 0;
        _configuredProxyPort = null;
        _failPendingRequests(StateError('Telegram 插件连接已断开'));
        authStep.value = TelegramAuthStep.error;
      });
      _clientId = await _plugin.createClient();
    }
    authStep.value = TelegramAuthStep.loading;
    // Do NOT configure the proxy here: before setTdlibParameters, TDLib is in
    // authorizationStateWaitTdlibParameters and rejects addProxy (no binlog yet). Sending it now
    // makes configureProxyIfAvailable throw and aborts login. The proxy is applied right after
    // setTdlibParameters instead (see _handleAuthorizationState).
    await _enqueueAuthorizationState(await _request('getAuthorizationState'));
  }

  Future<void> submitPhone(String phoneNumber) async {
    await configureProxyIfAvailable();
    await _expectOk('setAuthenticationPhoneNumber', <String, Object?>{
      'phone_number': phoneNumber,
      'settings': null,
    });
  }

  Future<void> submitCode(String code) {
    return _expectOk('checkAuthenticationCode', <String, Object?>{
      'code': code,
    });
  }

  Future<void> submitPassword(String password) {
    return _expectOk('checkAuthenticationPassword', <String, Object?>{
      'password': password,
    });
  }

  Future<List<TelegramMessagePreview>> fetchLatest(String rawUsername) async {
    await configureProxyIfAvailable();
    _ensureReady();
    final chat = await _resolveChat(rawUsername);
    final response = await _request('getChatHistory', <String, Object?>{
      'chat_id': (chat['id'] as num).toInt(),
      'from_message_id': 0,
      'offset': 0,
      'limit': 10,
      'only_local': false,
    });
    _throwIfError(response);
    return _codec
        .mapList(response['messages'])
        .map(_codec.messagePreview)
        .toList(growable: false);
  }

  Future<void> sendCommand(String rawUsername, String command) async {
    await configureProxyIfAvailable();
    _ensureReady();
    final chat = await _resolveChat(rawUsername);
    await _sendText((chat['id'] as num).toInt(), command, disablePreview: true);
  }

  Future<List<TelegramChatSummary>> loadChats({int limit = 30}) async {
    await configureProxyIfAvailable();
    _ensureReady();
    final loadResponse = await _request('loadChats', <String, Object?>{
      'chat_list': null,
      'limit': limit,
    });
    if (_codec.isError(loadResponse) && _codec.errorCode(loadResponse) != 404) {
      _throwIfError(loadResponse);
    }
    final response = await _request('getChats', <String, Object?>{
      'chat_list': null,
      'limit': limit,
    });
    _throwIfError(response);
    final chatIds =
        (response['chat_ids'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<num>();
    final chats = await Future.wait(
      chatIds.map((chatId) async {
        final chat = await _request('getChat', <String, Object?>{
          'chat_id': chatId.toInt(),
        });
        return _codec.isError(chat) ? null : _codec.chatSummary(chat);
      }),
    );
    return chats.whereType<TelegramChatSummary>().toList(growable: false);
  }

  Future<TelegramChatSummary> resolvePublicChat(String rawUsername) async {
    await configureProxyIfAvailable();
    _ensureReady();
    return _codec.chatSummary(await _resolveChat(rawUsername));
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
      await _expectOk('openChat', <String, Object?>{'chat_id': chatId});
    }
    final response = await _request('getChatHistory', <String, Object?>{
      'chat_id': chatId,
      'from_message_id': fromMessageId,
      'offset': 0,
      'limit': limit,
      'only_local': false,
    });
    _throwIfError(response);
    final messages = _codec
        .mapList(response['messages'])
        .map(_codec.messagePreview)
        .toList(growable: false);
    if (isLatestPage && messages.isNotEmpty) {
      await _expectOk('viewMessages', <String, Object?>{
        'chat_id': chatId,
        'message_ids': messages.map((message) => message.id).toList(),
        'source': null,
        'force_read': true,
      });
    }
    return messages;
  }

  Future<void> closeChat(int chatId) async {
    if (_clientId == 0) return;
    await _expectOk('closeChat', <String, Object?>{'chat_id': chatId});
  }

  Future<void> sendText(int chatId, String text) async {
    await configureProxyIfAvailable();
    _ensureReady();
    await _sendText(chatId, text);
  }

  Future<void> logout() async {
    await configureProxyIfAvailable();
    _ensureReady();
    await _expectOk('logOut');
    authStep.value = TelegramAuthStep.loading;
  }

  Future<void> _sendText(
    int chatId,
    String text, {
    bool disablePreview = false,
  }) async {
    final response = await _request('sendMessage', <String, Object?>{
      'chat_id': chatId,
      'message_thread_id': 0,
      'input_message_content': <String, Object?>{
        '@type': 'inputMessageText',
        'text': <String, Object?>{
          '@type': 'formattedText',
          'text': text,
          'entities': <Object?>[],
        },
        'disable_web_page_preview': disablePreview,
        'clear_draft': true,
      },
    });
    _throwIfError(response);
  }

  Future<TelegramJson> _resolveChat(String rawUsername) async {
    final username = rawUsername.trim().replaceFirst(RegExp(r'^@'), '');
    final response = await _request('searchPublicChat', <String, Object?>{
      'username': username,
    });
    _throwIfError(response);
    return response;
  }

  Future<void> configureProxyIfAvailable() async {
    if (_clientId == 0) return;
    final port = await proxyEndpointProvider.resolveAvailableLocalSocks5Port();
    if (port == null) {
      if (_configuredProxyPort != null) {
        await _expectOk('disableProxy');
        _configuredProxyPort = null;
      }
      proxyStatus.value = '本地代理未运行，TDLib 将尝试直连';
      return;
    }
    if (_configuredProxyPort == port) {
      proxyStatus.value = '已使用本地代理 127.0.0.1:$port';
      return;
    }
    final response = await _request('addProxy', <String, Object?>{
      'server': '127.0.0.1',
      'port': port,
      'enable': true,
      'type': <String, Object?>{
        '@type': 'proxyTypeSocks5',
        'username': '',
        'password': '',
      },
    });
    _throwIfError(response, statusPrefix: '代理启用失败');
    _configuredProxyPort = port;
    proxyStatus.value = '已使用本地代理 127.0.0.1:$port';
  }

  Future<void> _handleAuthorizationState(TelegramJson state) async {
    switch (state['@type']) {
      case 'authorizationStateWaitTdlibParameters':
        final config = _config;
        if (config == null || !config.hasApiCredentials) {
          authStep.value = TelegramAuthStep.error;
          return;
        }
        await _expectOk('setTdlibParameters', <String, Object?>{
          'use_test_dc': false,
          'database_directory': '',
          'files_directory': '',
          'database_encryption_key': '',
          'use_file_database': false,
          'use_chat_info_database': true,
          'use_message_database': true,
          'use_secret_chats': false,
          'api_id': config.apiId,
          'api_hash': config.apiHash,
          'system_language_code': 'zh-Hans',
          'device_model': 'Android',
          'system_version': Platform.operatingSystemVersion,
          'application_version': '1.0.1',
          'enable_storage_optimizer': true,
          'ignore_file_names': true,
        });
        // Apply the local SOCKS5 proxy immediately after parameters are set. TDLib only accepts
        // addProxy once the binlog exists, and applying it here (before it settles on a route)
        // keeps the initial connection on the proxy instead of racing a direct connection.
        await configureProxyIfAvailable();
      case 'authorizationStateWaitPhoneNumber':
        await configureProxyIfAvailable();
        authStep.value = TelegramAuthStep.phone;
      case 'authorizationStateWaitCode':
        await configureProxyIfAvailable();
        authStep.value = TelegramAuthStep.code;
      case 'authorizationStateWaitPassword':
        await configureProxyIfAvailable();
        authStep.value = TelegramAuthStep.password;
      case 'authorizationStateReady':
        await configureProxyIfAvailable();
        authStep.value = TelegramAuthStep.ready;
      case 'authorizationStateClosed':
        _clientId = 0;
        _configuredProxyPort = null;
        _failPendingRequests(StateError('Telegram 连接已关闭'));
        authStep.value = TelegramAuthStep.loggedOut;
    }
  }

  Future<void> _enqueueAuthorizationState(TelegramJson state) {
    _authorizationQueue = _authorizationQueue
        .then((_) => _handleAuthorizationState(state))
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('Telegram authorization update failed: $error');
          authStep.value = TelegramAuthStep.error;
        });
    return _authorizationQueue;
  }

  void _handleRawResult(String rawResult) {
    try {
      final object = _codec.decodeObject(rawResult);
      final clientId = (object['@client_id'] as num?)?.toInt();
      if (clientId != null && clientId != _clientId) return;
      final extra = object['@extra']?.toString();
      if (extra != null) {
        _requests.remove(extra)?.complete(object);
      }
      if (object['@type'] == 'updateAuthorizationState') {
        unawaited(
          _enqueueAuthorizationState(
            _codec.mapOrEmpty(object['authorization_state']),
          ),
        );
      }
    } catch (error) {
      debugPrint('Telegram plugin returned invalid JSON: $error');
    }
  }

  Future<TelegramJson> _request(
    String type, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    if (_clientId == 0) {
      throw StateError('Telegram 客户端尚未启动');
    }
    final extra = 'tg_${_requestId++}';
    final completer = Completer<TelegramJson>();
    _requests[extra] = completer;
    try {
      await _plugin.send(
        clientId: _clientId,
        requestJson: _codec.encodeRequest(
          type,
          arguments: arguments,
          extra: extra,
        ),
      );
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
        throw TimeoutException('Telegram 请求超时：$type');
      },
    );
  }

  Future<void> _expectOk(
    String type, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    _throwIfError(await _request(type, arguments));
  }

  void _throwIfError(TelegramJson response, {String? statusPrefix}) {
    if (!_codec.isError(response)) return;
    final message = _codec.errorMessage(response);
    if (statusPrefix != null) {
      proxyStatus.value = '$statusPrefix：$message';
    }
    throw StateError(message);
  }

  void _failPendingRequests(Object error) {
    final requests = _requests.values.toList(growable: false);
    _requests.clear();
    for (final request in requests) {
      if (!request.isCompleted) request.completeError(error);
    }
  }

  void _ensureReady() {
    if (authStep.value != TelegramAuthStep.ready) {
      throw StateError('Telegram 账号尚未登录');
    }
  }
}

class _NullProxyEndpointProvider implements LocalProxyEndpointProvider {
  const _NullProxyEndpointProvider();

  @override
  int? get localSocks5Port => null;

  @override
  Future<int?> resolveAvailableLocalSocks5Port() async => null;
}
