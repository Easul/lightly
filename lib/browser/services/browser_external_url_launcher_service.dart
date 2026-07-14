import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

typedef ExternalUrlLaunchCallback =
    Future<bool> Function(Uri url, {LaunchMode mode});

class BrowserExternalUrlLauncherService {
  BrowserExternalUrlLauncherService({ExternalUrlLaunchCallback? launch})
    : _launch = launch ?? launchUrl;

  final ExternalUrlLaunchCallback _launch;

  static const String launchedMessage = '已尝试打开外部应用';
  static const String unavailableMessage = '当前设备无法处理该外部跳转';
  static const String failedMessage = '打开外部应用失败';

  Future<String> launch(Uri requestedUrl) async {
    if (kDebugMode || kProfileMode) {
      final url = requestedUrl.toString();
      debugPrint(
        '[ExternalUrlLaunch] scheme=${requestedUrl.scheme} '
        'length=${url.length} '
        'camelMethod=${url.contains('jumpToSharedProduct')} '
        'lowerMethod=${url.contains('jumptosharedproduct')} '
        'camelTrafficTag=${url.contains('trafficTag')} '
        'lowerTrafficTag=${url.contains('traffictag')}',
      );
    }
    try {
      final launched = await _launch(
        requestedUrl,
        mode: LaunchMode.externalApplication,
      );
      return launched ? launchedMessage : unavailableMessage;
    } catch (_) {
      return failedMessage;
    }
  }
}
