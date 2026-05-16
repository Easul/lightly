import 'dart:io';

import 'package:flutter/services.dart';

class MediaScannerService {
  static const MethodChannel _channel = MethodChannel('media_scanner');

  /// 扫描新下载的文件，让系统文件管理器可以看到
  static Future<bool> scanFile(String filePath) async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('scanFile', {
          'filePath': filePath,
        });
        return result ?? false;
      } catch (e) {
        return false;
      }
    }
    return true;
  }

  /// 扫描整个目录
  static Future<bool> scanDirectory(String directoryPath) async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('scanDirectory', {
          'directoryPath': directoryPath,
        });
        return result ?? false;
      } catch (e) {
        return false;
      }
    }
    return true;
  }
}
