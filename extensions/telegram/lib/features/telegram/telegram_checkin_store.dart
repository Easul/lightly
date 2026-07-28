import 'dart:convert';

import 'telegram_checkin_models.dart';
import 'telegram_host_gateway.dart';

class TelegramCheckinStore {
  TelegramCheckinStore({TelegramHostGateway? gateway})
    : _gateway = gateway ?? TelegramHostGateway.instance;

  final TelegramHostGateway _gateway;

  Future<TelegramCheckinConfig> load() async {
    final raw = await _gateway.readTelegramConfig();
    if (raw == null || raw.isEmpty) {
      return const TelegramCheckinConfig();
    }
    return TelegramCheckinConfig.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  Future<void> save(TelegramCheckinConfig config) {
    return _gateway.writeTelegramConfig(jsonEncode(config.toJson()));
  }
}
