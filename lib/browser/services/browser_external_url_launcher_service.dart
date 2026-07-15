import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_log_service.dart';
import '../utils/browser_popup_url_decoder.dart';

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
    final launchUrl = _prepareLaunchUrl(requestedUrl);
    if (kDebugMode || kProfileMode) {
      final url = launchUrl.toString();
      debugPrint(
        '[ExternalUrlLaunch] scheme=${launchUrl.scheme} '
        'length=${url.length} '
        'camelMethod=${url.contains('jumpToSharedProduct')} '
        'lowerMethod=${url.contains('jumptosharedproduct')} '
        'camelTrafficTag=${url.contains('trafficTag')} '
        'lowerTrafficTag=${url.contains('traffictag')}',
      );
    }
    try {
      final launched = await _launch(
        launchUrl,
        mode: LaunchMode.externalApplication,
      );
      return launched ? launchedMessage : unavailableMessage;
    } catch (error, stackTrace) {
      recordRuntimeLog(
        'ExternalUrlLaunch',
        'External application launch failed',
        error: error,
        stackTrace: stackTrace,
        metadata: <String, Object?>{'scheme': launchUrl.scheme},
      );
      return failedMessage;
    }
  }

  Uri _prepareLaunchUrl(Uri requestedUrl) {
    final rawUrl = requestedUrl is WebUri
        ? requestedUrl.rawValue
        : requestedUrl.toString();
    final decodedUrl = BrowserPopupUrlDecoder.decodeIfNeeded(rawUrl);
    final externalUrl = BrowserPopupUrlDecoder.externalLaunchUrl(
      rawUrl: rawUrl,
      decodedUrl: decodedUrl,
    );
    return WebUri(externalUrl, forceToStringRawValue: true);
  }
}
