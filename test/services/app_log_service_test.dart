import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/core/logging/runtime_logger.dart';
import 'package:lightly/core/storage/shared_downloads_access.dart';
import 'package:lightly/services/app_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('re-enabling logging clears the previous log session', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final directory = await Directory.systemTemp.createTemp('app-log-test-');
    final logFile = File('${directory.path}/runtime.log');
    await logFile.writeAsString('previous session\n');
    final service = AppLogService.forTesting(logFile: logFile, enabled: true);

    try {
      await service.log('old event');
      await service.setEnabled(false);
      expect(await logFile.exists(), isFalse);
      await service.setEnabled(true);
      await service.log('new event');

      final contents = await service.readLogContents();
      expect(contents, isNot(contains('previous session')));
      expect(contents, isNot(contains('old event')));
      expect(contents, contains('Runtime logging enabled'));
      expect(contents, contains('new event'));
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('recordRuntimeLog writes scoped metadata to the runtime log', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final directory = await Directory.systemTemp.createTemp('runtime-log-');
    final logFile = File('${directory.path}/runtime.log');
    final service = AppLogService.forTesting(logFile: logFile, enabled: true);

    try {
      await recordRuntimeLog(
        'ProxyCore',
        'Native proxy start failed',
        error: StateError('test failure'),
        metadata: <String, Object?>{'protocol': 'vless'},
        service: service,
      );

      final contents = await service.readLogContents();
      expect(contents, contains('[ProxyCore] Native proxy start failed'));
      expect(contents, contains('"protocol":"vless"'));
      expect(contents, contains('test failure'));
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('recordRuntimeLog writes through an injected RuntimeLogger', () async {
    final logger = _RecordingRuntimeLogger();

    await recordRuntimeLog('Backup', 'Export failed', service: logger);

    expect(logger.messages, <String>['[Backup] Export failed']);
  });

  test('log export uses injected shared Downloads access', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final directory = await Directory.systemTemp.createTemp('app-log-export-');
    final logFile = File('${directory.path}/runtime.log');
    final exportDirectory = Directory('${directory.path}/exports');
    final downloadsAccess = _FakeSharedDownloadsAccess(exportDirectory);
    final service = AppLogService.forTesting(
      logFile: logFile,
      enabled: true,
      sharedDownloadsAccess: downloadsAccess,
    );

    try {
      await service.log('exported event');
      final exported = await service.exportLogToDownloads(
        requestSharedAccessIfNeeded: true,
      );

      expect(exported.parent.path, exportDirectory.path);
      expect(await exported.readAsString(), contains('exported event'));
      expect(downloadsAccess.requestSharedAccessIfNeeded, isTrue);
      expect(downloadsAccess.androidFallbackFolderName, 'exports');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('runtime log redacts sensitive metadata and URL payloads', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final directory = await Directory.systemTemp.createTemp('runtime-log-');
    final logFile = File('${directory.path}/runtime.log');
    final service = AppLogService.forTesting(logFile: logFile, enabled: true);

    try {
      await service.log(
        'Failed https://example.com/watch?id=secret#fragment '
        'bankabc://%7B%22token%22%3A%22secret%22%7D',
        error: PlatformException(
          code: 'failed',
          message: 'Request https://example.com/api?token=secret failed',
          details: <String, Object?>{'password': 'secret'},
        ),
        metadata: <String, Object?>{
          'url': 'https://example.com/path?token=secret#fragment',
          'token': 'secret',
          'nested': <String, Object?>{'cookie': 'session=secret'},
        },
      );

      final contents = await service.readLogContents();
      expect(contents, contains('https://example.com/watch'));
      expect(contents, contains('bankabc://<redacted>'));
      expect(contents, contains('"token":"<redacted>"'));
      expect(contents, contains('"cookie":"<redacted>"'));
      expect(contents, isNot(contains('secret')));
      expect(contents, isNot(contains('fragment')));
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

class _RecordingRuntimeLogger implements RuntimeLogger {
  final List<String> messages = <String>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> log(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? metadata,
  }) async {
    messages.add(message);
  }

  @override
  Future<void> logFlutterError(FlutterErrorDetails details) async {}

  @override
  Future<void> logUnhandledError(Object error, StackTrace stackTrace) async {}
}

class _FakeSharedDownloadsAccess implements SharedDownloadsAccess {
  _FakeSharedDownloadsAccess(this.directory);

  final Directory directory;
  bool? requestSharedAccessIfNeeded;
  String? androidFallbackFolderName;

  @override
  Future<String?> getSharedDownloadsPath() async => directory.path;

  @override
  Future<bool> hasFileAccessPermission() async => true;

  @override
  Future<bool> requestFileAccessPermission() async => true;

  @override
  Future<Directory> resolveDirectory({
    bool preferSharedDownloads = true,
    bool requestSharedAccessIfNeeded = false,
    String androidFallbackFolderName = 'browser_downloads',
    String nonAndroidFallbackFolderName = 'downloads',
  }) async {
    this.requestSharedAccessIfNeeded = requestSharedAccessIfNeeded;
    this.androidFallbackFolderName = androidFallbackFolderName;
    await directory.create(recursive: true);
    return directory;
  }
}
