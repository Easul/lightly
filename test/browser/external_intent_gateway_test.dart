import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/external_intent_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('external_intent_gateway_test');
  final gateway = ExternalIntentGateway(channel: channel);
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'getInitialIntentUrl' => 'content://initial',
            'detachExternalIntent' => true,
            'getContentMimeType' => 'text/plain',
            'importContentUriToPrivateFile' => 'file:///private/import.txt',
            'cleanupImportedPrivateFiles' => true,
            _ => null,
          };
        });
  });

  tearDown(() {
    gateway.setNewIntentUrlHandler(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('gets and detaches the initial external intent', () async {
    expect(await gateway.getInitialIntentUrl(), 'content://initial');
    expect(await gateway.detachExternalIntent(), isTrue);
    expect(calls.map((call) => call.method), <String>[
      'getInitialIntentUrl',
      'detachExternalIntent',
    ]);
  });

  test('gets a content URI MIME type', () async {
    expect(
      await gateway.getContentMimeType('content://document/1'),
      'text/plain',
    );
    expect(calls.single.method, 'getContentMimeType');
    expect(calls.single.arguments, <String, Object?>{
      'uri': 'content://document/1',
    });
  });

  test('imports a content URI into a private file', () async {
    expect(
      await gateway.importContentUriToPrivateFile('content://document/1'),
      'file:///private/import.txt',
    );
    expect(calls.single.method, 'importContentUriToPrivateFile');
    expect(calls.single.arguments, <String, Object?>{
      'uri': 'content://document/1',
    });
  });

  test('cleans imported files while retaining supplied URLs', () async {
    const retainedUrls = <String>['file:///private/keep.txt'];
    expect(await gateway.cleanupImportedPrivateFiles(retainedUrls), isTrue);
    expect(calls.single.method, 'cleanupImportedPrivateFiles');
    expect(calls.single.arguments, <String, Object?>{
      'retainedUrls': retainedUrls,
    });
  });

  test('maps new-intent callbacks to a URL handler', () async {
    final receivedUrl = Completer<String?>();
    gateway.setNewIntentUrlHandler((url) async {
      receivedUrl.complete(url);
    });

    final message = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('onNewIntentUrl', <String, Object?>{
        'url': 'https://example.com',
      }),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, message, (_) {});

    expect(await receivedUrl.future, 'https://example.com');
  });
}
