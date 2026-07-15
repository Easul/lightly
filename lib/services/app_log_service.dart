import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_downloads_directory_service.dart';

Future<void> recordRuntimeLog(
  String scope,
  String message, {
  Object? error,
  StackTrace? stackTrace,
  Map<String, Object?>? metadata,
  AppLogService? service,
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

class AppLogService {
  AppLogService._();

  @visibleForTesting
  AppLogService.forTesting({required File logFile, bool enabled = false})
    : _logFile = logFile,
      _initialized = true,
      _enabled = enabled;

  static final AppLogService instance = AppLogService._();
  static const String _enabledPreferenceKey = 'app_log_enabled';
  static const Set<String> _sensitiveMetadataKeys = <String>{
    'authorization',
    'clipboard',
    'config',
    'content',
    'cookie',
    'credentials',
    'password',
    'payload',
    'proxyconfig',
    'secret',
    'token',
  };
  static final RegExp _nonLetterPattern = RegExp(r'[^a-z]');
  static final RegExp _urlPattern = RegExp(
    r"""[A-Za-z][A-Za-z0-9+.-]*://[^\s<>"']+""",
  );
  static final RegExp _authorizationHeaderPattern = RegExp(
    r'\b(Bearer|Basic)\s+\S+',
    caseSensitive: false,
  );
  static final RegExp _sensitiveAssignmentPattern = RegExp(
    r'''("?(?:password|token|secret|cookie|authorization)"?\s*[:=]\s*)("[^"]*"|[^,\s}]+)''',
    caseSensitive: false,
  );

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
    final safeMetadata = _sanitizeMetadata(metadata);
    final buffer = StringBuffer()
      ..writeln('=== ${DateTime.now().toIso8601String()} ===')
      ..writeln(_sanitizeText(message, maxLength: 4000));
    if (safeMetadata != null && safeMetadata.isNotEmpty) {
      buffer.writeln(jsonEncode(safeMetadata));
    }
    if (error != null) {
      buffer.writeln('ERROR: ${_sanitizeError(error)}');
    }
    if (stackTrace != null) {
      buffer.writeln(_sanitizeText(stackTrace.toString(), maxLength: 12000));
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

  Object _sanitizeError(Object error) {
    if (error is PlatformException) {
      return _sanitizeText(
        'PlatformException(${error.code}): ${error.message ?? 'No message'}',
        maxLength: 2000,
      );
    }
    return _sanitizeText(error.toString(), maxLength: 2000);
  }

  Map<String, Object?>? _sanitizeMetadata(Map<String, Object?>? metadata) {
    if (metadata == null || metadata.isEmpty) {
      return metadata;
    }
    return <String, Object?>{
      for (final entry in metadata.entries.take(50))
        entry.key: _sanitizeMetadataValue(entry.key, entry.value, depth: 0),
    };
  }

  Object? _sanitizeMetadataValue(
    String key,
    Object? value, {
    required int depth,
  }) {
    if (_isSensitiveMetadataKey(key)) {
      return '<redacted>';
    }
    if (value == null || value is num || value is bool) {
      return value;
    }
    if (value is String) {
      return _sanitizeText(value, maxLength: 1000);
    }
    if (depth >= 3) {
      return '<truncated>';
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries.take(30))
          entry.key.toString(): _sanitizeMetadataValue(
            entry.key.toString(),
            entry.value,
            depth: depth + 1,
          ),
      };
    }
    if (value is Iterable) {
      return value
          .take(30)
          .map((item) => _sanitizeMetadataValue('', item, depth: depth + 1))
          .toList(growable: false);
    }
    return _sanitizeText(value.toString(), maxLength: 1000);
  }

  bool _isSensitiveMetadataKey(String key) {
    final normalized = key.toLowerCase().replaceAll(_nonLetterPattern, '');
    if (_sensitiveMetadataKeys.contains(normalized)) {
      return true;
    }
    return normalized.endsWith('apikey') ||
        normalized.endsWith('clipboardcontent') ||
        normalized.endsWith('cookievalue') ||
        normalized.endsWith('credential') ||
        normalized.endsWith('password') ||
        normalized.endsWith('payload') ||
        normalized.endsWith('secret') ||
        normalized.endsWith('streamurl') ||
        normalized.endsWith('token') ||
        normalized.endsWith('uploadkey');
  }

  String _sanitizeText(String value, {required int maxLength}) {
    final inputLimit = maxLength * 4;
    final boundedValue = value.length <= inputLimit
        ? value
        : value.substring(0, inputLimit);
    var sanitized = boundedValue.replaceAllMapped(_urlPattern, (match) {
      final rawUrl = match.group(0)!;
      final uri = Uri.tryParse(rawUrl);
      final scheme =
          uri?.scheme.toLowerCase() ??
          rawUrl.substring(0, rawUrl.indexOf(':')).toLowerCase();
      if (uri == null || (scheme != 'http' && scheme != 'https')) {
        return '$scheme://<redacted>';
      }
      return Uri(
        scheme: scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
      ).toString();
    });
    sanitized = sanitized.replaceAllMapped(
      _authorizationHeaderPattern,
      (match) => '${match.group(1)} <redacted>',
    );
    sanitized = sanitized.replaceAllMapped(
      _sensitiveAssignmentPattern,
      (match) => '${match.group(1)}<redacted>',
    );
    if (sanitized.length <= maxLength) {
      return sanitized;
    }
    return '${sanitized.substring(0, maxLength)}…';
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
