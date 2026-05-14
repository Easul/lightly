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
