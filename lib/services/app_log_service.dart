import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_downloads_directory_service.dart';

class AppLogService {
  AppLogService._();

  static final AppLogService instance = AppLogService._();
  static const String _enabledPreferenceKey = 'app_log_enabled';

  File? _logFile;
  bool _initialized = false;
  bool _enabled = false;
  Future<void> _pendingWrites = Future<void>.value();
  final SharedDownloadsDirectoryService _downloadsDirectoryService =
      SharedDownloadsDirectoryService();

  bool get isEnabled => _enabled;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    _enabled = preferences.getBool(_enabledPreferenceKey) ?? false;
    _initialized = true;

    if (!_enabled) {
      return;
    }

    await _ensureLogFile();
    await log(
      'AppLogService initialized',
      metadata: <String, Object?>{
        'logPath': _logFile?.path,
        'platform': Platform.operatingSystem,
        'flutterMode': kReleaseMode
            ? 'release'
            : kProfileMode
            ? 'profile'
            : 'debug',
      },
    );
  }

  Future<void> setEnabled(bool enabled) async {
    await initialize();
    if (_enabled == enabled) {
      return;
    }

    if (_enabled && !enabled) {
      await _writeLogEntry('Runtime logging disabled');
    }

    _enabled = enabled;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledPreferenceKey, enabled);

    if (!enabled) {
      return;
    }

    await _ensureLogFile();
    await _writeLogEntry(
      'Runtime logging enabled',
      metadata: <String, Object?>{'logPath': _logFile?.path},
    );
  }

  Future<void> _ensureLogFile() async {
    if (_logFile != null) {
      return;
    }

    final baseDir =
        await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final logsDir = Directory(path.join(baseDir.path, 'logs'));
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }

    _logFile = File(path.join(logsDir.path, 'runtime.log'));
  }

  String? get logPath => _logFile?.path;

  Future<void> log(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? metadata,
  }) async {
    if (!_initialized) {
      try {
        await initialize();
      } catch (_) {
        return;
      }
    }

    if (!_enabled) {
      return;
    }

    await _ensureLogFile();
    await _writeLogEntry(
      message,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  Future<void> _writeLogEntry(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? metadata,
  }) {
    final buffer = StringBuffer()
      ..writeln('=== ${DateTime.now().toIso8601String()} ===')
      ..writeln(message);
    if (metadata != null && metadata.isNotEmpty) {
      buffer.writeln(jsonEncode(metadata));
    }
    if (error != null) {
      buffer.writeln('ERROR: $error');
    }
    if (stackTrace != null) {
      buffer.writeln(stackTrace.toString());
    }
    buffer.writeln();

    final write = _pendingWrites.then((_) async {
      await _ensureLogFile();
      final file = _logFile;
      if (file == null) {
        return;
      }
      await file.writeAsString(
        buffer.toString(),
        mode: FileMode.append,
        flush: true,
      );
    });
    _pendingWrites = write.catchError((_) {});
    return write;
  }

  Future<void> logFlutterError(FlutterErrorDetails details) async {
    await log(
      'FlutterError',
      error: details.exception,
      stackTrace: details.stack,
      metadata: <String, Object?>{
        'library': details.library,
        'context': details.context?.toDescription(),
      },
    );
  }

  Future<void> logUnhandledError(Object error, StackTrace stackTrace) async {
    await log('Unhandled Dart error', error: error, stackTrace: stackTrace);
  }

  Future<String> readLogContents() async {
    if (!_initialized) {
      await initialize();
    }
    await _pendingWrites;
    final file = _logFile;
    if (file == null || !await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  Future<File> exportLogToDownloads({
    bool requestSharedAccessIfNeeded = true,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    await _pendingWrites;
    final source = _logFile;
    if (source == null || !await source.exists()) {
      throw StateError('runtime.log not found');
    }

    final downloadDirectory = await _downloadsDirectoryService.resolveDirectory(
      preferSharedDownloads: true,
      requestSharedAccessIfNeeded: requestSharedAccessIfNeeded,
      androidFallbackFolderName: 'exports',
      nonAndroidFallbackFolderName: 'exports',
    );

    final now = DateTime.now();
    final timestamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
        '-${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
    final destination = File(
      path.join(downloadDirectory.path, 'ruoqing-runtime-log-$timestamp.log'),
    );
    return source.copy(destination.path);
  }

  Future<void> copyLogToClipboard() async {
    final contents = await readLogContents();
    await Clipboard.setData(ClipboardData(text: contents));
  }
}
