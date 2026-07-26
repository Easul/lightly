import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/local_sharing/clipboard/clipboard_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = SystemChannels.platform;
  late List<MethodCall> clipboardCalls;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    clipboardCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method.startsWith('Clipboard.')) {
            clipboardCalls.add(call);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('saveContent persists data without writing system clipboard', () async {
    final service = ClipboardStorageService();

    await service.saveContent('saved text');

    expect(await service.loadContent(), 'saved text');
    expect(clipboardCalls, isEmpty);
  });

  test(
    'clearContent clears stored data without clearing system clipboard',
    () async {
      final service = ClipboardStorageService();
      await service.saveContent('saved text');
      clipboardCalls.clear();

      await service.clearContent();

      expect(await service.loadContent(), isEmpty);
      expect(clipboardCalls, isEmpty);
    },
  );
}
