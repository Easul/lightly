import 'package:flutter_test/flutter_test.dart';
import 'package:telegram/features/telegram/telegram_checkin_models.dart';

void main() {
  test('telegram config keeps backup-compatible JSON fields', () {
    const config = TelegramCheckinConfig(
      apiId: 123,
      apiHash: 'hash',
      phoneNumber: '+861380000000000',
      targets: <TelegramCheckinTarget>[
        TelegramCheckinTarget(
          id: 'target',
          username: '@bot',
          command: '/checkin',
          enabled: false,
        ),
      ],
    );

    final restored = TelegramCheckinConfig.fromJson(config.toJson());

    expect(restored.apiId, config.apiId);
    expect(restored.apiHash, config.apiHash);
    expect(restored.phoneNumber, config.phoneNumber);
    expect(restored.targets.single.enabled, isFalse);
  });
}
