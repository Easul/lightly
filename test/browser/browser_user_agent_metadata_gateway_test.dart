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
    ).prepareWebView(webViewId: 'tab-1', desktopUserAgent: 'Desktop UA');

    expect(applied, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'prepareBrowserWebView');
    expect(calls.single.arguments, <String, Object?>{
      'webViewId': 'tab-1',
      'desktopUserAgent': 'Desktop UA',
    });
  });

  test('prepares a mobile WebView without desktop metadata', () async {
    const channel = MethodChannel('test_browser_mobile_webview_preparation');
    MethodCall? recordedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          recordedCall = call;
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final prepared = await const BrowserUserAgentMetadataGateway(
      channel: channel,
    ).prepareWebView(webViewId: 'tab-2');

    expect(prepared, isTrue);
    expect(recordedCall?.method, 'prepareBrowserWebView');
    expect(recordedCall?.arguments, <String, Object?>{
      'webViewId': 'tab-2',
      'desktopUserAgent': null,
    });
  });
}
