import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TelegramHostContext {
  const TelegramHostContext({
    this.hostPackage = 'lightly.tool',
    this.dataAuthority = 'lightly.tool.optional_plugins.data',
    this.proxyPort,
  });

  final String hostPackage;
  final String dataAuthority;
  final int? proxyPort;

  factory TelegramHostContext.fromMap(Map<Object?, Object?>? value) {
    return TelegramHostContext(
      hostPackage: value?['hostPackage'] as String? ?? 'lightly.tool',
      dataAuthority:
          value?['dataAuthority'] as String? ??
          'lightly.tool.optional_plugins.data',
      proxyPort: (value?['proxyPort'] as num?)?.toInt(),
    );
  }
}

class TelegramHostGateway {
  TelegramHostGateway({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const String channelName = 'lightly.telegram_plugin/host';
  static final TelegramHostGateway instance = TelegramHostGateway();

  final MethodChannel _channel;
  final ValueNotifier<TelegramHostContext> context =
      ValueNotifier<TelegramHostContext>(const TelegramHostContext());

  Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'hostContextChanged') {
        return;
      }
      context.value = TelegramHostContext.fromMap(
        (call.arguments as Map?)?.cast<Object?, Object?>(),
      );
    });
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getHostContext',
    );
    context.value = TelegramHostContext.fromMap(value);
  }

  Future<String?> readTelegramConfig() {
    return _channel.invokeMethod<String>('readTelegramConfig');
  }

  Future<void> writeTelegramConfig(String json) async {
    final updated = await _channel.invokeMethod<bool>('writeTelegramConfig', {
      'json': json,
    });
    if (updated != true) {
      throw StateError('Lightly 未接受 Telegram 配置更新');
    }
  }
}
