import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logging/runtime_logger.dart';
import '../core/storage/shared_downloads_access.dart';
import 'runtime_log_sanitizer.dart';
import 'shared_downloads_directory_service.dart';

Future<void> recordRuntimeLog(
  String scope,
  String message, {
  Object? error,
  StackTrace? stackTrace,
  Map<String, Object?>? metadata,
  RuntimeLogger? service,
}) {
  developer.log(message, name: scope, error: error, stackTrace: stackTrace);
  return (service ?? AppLogService.instance)
      .log(
        '[$scope] $message',
        error: error,
        stackTrace: stackTrace,
        metadata: metadata,
      )
      .catchError((_) {});
}

class AppLogService implements RuntimeLogger {
  AppLogService._({SharedDownloadsAccess? sharedDownloadsAccess})
    : _sharedDownloadsAccess =
          sharedDownloadsAccess ?? SharedDownloadsDirectoryService();

  @visibleForTesting
  AppLogService.forTesting({
    required File logFile,
    bool enabled = false,
    SharedDownloadsAccess? sharedDownloadsAccess,
  }) : _sharedDownloadsAccess =
           sharedDownloadsAccess ?? SharedDownloadsDirectoryService(),
       _logFile = logFile,
       _initialized = true,
       _enabled = enabled;

  static final AppLogService instance = AppLogService._();
  static const String _enabledPreferenceKey = 'app_log_enabled';

  File? _logFile;
  bool _initialized = false;
  bool _enabled = false;
  Future<void> _pendingWrites = Future<void>.value();
  final SharedDownloadsAccess _sharedDownloadsAccess;
  final RuntimeLogSanitizer _sanitizer = const RuntimeLogSanitizer();

  bool get isEnabled => _enabled;

  @override
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
      if (!enabled) {
        await _deleteLogFile();
      }
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    if (!enabled) {
      _enabled = false;
      await preferences.setBool(_enabledPreferenceKey, false);
      await _deleteLogFile();
      return;
    }

    await _resetLogFileForNewSession();
    _enabled = true;
    await preferences.setBool(_enabledPreferenceKey, true);
    await _writeLogEntry(
      'Runtime logging enabled',
      metadata: <String, Object?>{'logPath': _logFile?.path},
    );
  }

  Future<void> _resetLogFileForNewSession() async {
    await _pendingWrites;
    await _ensureLogFile();
    final file = _logFile;
    if (file == null) {
      return;
    }
    await file.writeAsString('', flush: true);
  }

  Future<void> _deleteLogFile() async {
    await _pendingWrites;
    final file = _logFile;
    if (file != null && await file.exists()) {
      await file.delete();
    }
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

  @override
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
    final safeMetadata = _sanitizer.sanitizeMetadata(metadata);
    final buffer = StringBuffer()
      ..writeln('=== ${DateTime.now().toIso8601String()} ===')
      ..writeln(_sanitizer.sanitizeMessage(message));
    if (safeMetadata != null && safeMetadata.isNotEmpty) {
      buffer.writeln(jsonEncode(safeMetadata));
    }
    if (error != null) {
      buffer.writeln('ERROR: ${_sanitizer.sanitizeError(error)}');
    }
    if (stackTrace != null) {
      buffer.writeln(_sanitizer.sanitizeStackTrace(stackTrace));
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

  @override
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

  @override
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

    final downloadDirectory = await _sharedDownloadsAccess.resolveDirectory(
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
