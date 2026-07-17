import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tdlib/td_api.dart' as td;
import 'package:tdlib/tdlib.dart';

import 'telegram_checkin_models.dart';

enum TelegramAuthStep { loading, phone, code, password, ready, error }

class TelegramTdlibService {
  TelegramTdlibService._();

  static final TelegramTdlibService instance = TelegramTdlibService._();

  final ValueNotifier<TelegramAuthStep> authStep =
      ValueNotifier<TelegramAuthStep>(TelegramAuthStep.loading);
  final Map<String, Completer<td.TdObject>> _requests =
      <String, Completer<td.TdObject>>{};
  int _clientId = 0;
  int _requestId = 0;
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
    } else if (state is td.AuthorizationStateWaitPhoneNumber) {
      authStep.value = TelegramAuthStep.phone;
    } else if (state is td.AuthorizationStateWaitCode) {
      authStep.value = TelegramAuthStep.code;
    } else if (state is td.AuthorizationStateWaitPassword) {
      authStep.value = TelegramAuthStep.password;
    } else if (state is td.AuthorizationStateReady) {
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
