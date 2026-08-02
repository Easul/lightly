import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_user_agent_metadata_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('passes the WebView id and desktop user agent to Android', () async {
    const channel = MethodChannel('test_browser_user_agent_metadata');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final applied = await const BrowserUserAgentMetadataGateway(
      channel: channel,
    ).applyDesktopMetadata(webViewId: 'tab-1', userAgent: 'Desktop UA');

    expect(applied, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'applyDesktopUserAgentMetadata');
    expect(calls.single.arguments, <String, Object>{
      'webViewId': 'tab-1',
      'userAgent': 'Desktop UA',
    });
  });
}
