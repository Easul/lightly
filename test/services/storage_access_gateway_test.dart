import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/services/storage_access_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('storage_access_gateway_test');
  final gateway = StorageAccessGateway(channel: channel);
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getSharedDownloadsPath') {
            return '/storage/emulated/0/Download';
          }
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('gets the shared Download path', () async {
    expect(
      await gateway.getSharedDownloadsPath(),
      '/storage/emulated/0/Download',
    );
    expect(calls.single.method, 'getSharedDownloadsPath');
    expect(calls.single.arguments, isNull);
  });

  test('checks shared file access permission', () async {
    expect(await gateway.hasFileAccessPermission(), isTrue);
    expect(calls.single.method, 'hasFileAccessPermission');
    expect(calls.single.arguments, isNull);
  });

  test('requests shared file access permission', () async {
    expect(await gateway.requestFileAccessPermission(), isTrue);
    expect(calls.single.method, 'requestFileAccessPermission');
    expect(calls.single.arguments, isNull);
  });
}
