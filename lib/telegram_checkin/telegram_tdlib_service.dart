import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tdlib/td_api.dart' as td;
import 'package:tdlib/tdlib.dart';

import '../browser/proxy_service.dart';
import 'telegram_checkin_models.dart';

enum TelegramAuthStep { loading, phone, code, password, ready, error }

class TelegramTdlibService {
  TelegramTdlibService._();

  static final TelegramTdlibService instance = TelegramTdlibService._();

  final ValueNotifier<TelegramAuthStep> authStep =
      ValueNotifier<TelegramAuthStep>(TelegramAuthStep.loading);
  final ValueNotifier<String> proxyStatus = ValueNotifier<String>('正在检查代理');
  final Map<String, Completer<td.TdObject>> _requests =
      <String, Completer<td.TdObject>>{};
  int _clientId = 0;
  int _requestId = 0;
  int? _configuredProxyPort;
  TelegramCheckinConfig? _config;

  Future<void> start(TelegramCheckinConfig config) async {
    _config = config;
    if (_clientId == 0) {
      _clientId = tdCreate();
      Timer.periodic(const Duration(milliseconds: 80), (_) => _drainUpdates());
    }
    authStep.value = TelegramAuthStep.loading;
    final state = await _request(const td.GetAuthorizationState());
    if (state is td.AuthorizationState) {
      await _handleAuthorizationState(state);
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
            text: text,
            date: DateTime.fromMillisecondsSinceEpoch(message.date * 1000),
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

  Future<td.Chat> _resolveChat(String rawUsername) async {
    final username = rawUsername.trim().replaceFirst(RegExp(r'^@'), '');
    final response = await _request(td.SearchPublicChat(username: username));
    if (response is td.TdError) throw StateError(response.message);
    return response as td.Chat;
  }

  Future<void> configureProxyIfAvailable() async {
    if (_clientId == 0) return;
    final proxyService = ProxyService();
    final port = proxyService.isRunning ? proxyService.localProxyPort : null;
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
    }
  }

  void _drainUpdates() {
    for (var index = 0; index < 20; index++) {
      final object = tdReceive(0);
      if (object == null) return;
      final extra = object.extra?.toString();
      if (extra != null) {
        _requests.remove(extra)?.complete(object);
      }
      if (object is td.UpdateAuthorizationState) {
        unawaited(_handleAuthorizationState(object.authorizationState));
      }
    }
  }

  Future<td.TdObject> _request(td.TdFunction function) {
    final extra = 'tg_${_requestId++}';
    final completer = Completer<td.TdObject>();
    _requests[extra] = completer;
    tdSend(_clientId, function, extra);
    return completer.future.timeout(const Duration(seconds: 30));
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
