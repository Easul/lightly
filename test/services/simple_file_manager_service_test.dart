import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lightly/core/logging/runtime_logger.dart';
import 'package:lightly/features/local_sharing/simple_file_manager/simple_file_manager_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SimpleFileManagerService service;
  late _FakeRuntimeLogger runtimeLogger;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('simple_file_manager_');
    runtimeLogger = _FakeRuntimeLogger();
    service = SimpleFileManagerService(runtimeLogger: runtimeLogger);
    await service.stop();
  });

  tearDown(() async {
    await service.stop();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('serves file tree, reads text, and saves changes', () async {
    final notesDir = Directory(p.join(tempDir.path, 'notes'));
    await notesDir.create();
    final file = File(p.join(notesDir.path, 'hello.md'));
    await file.writeAsString('# Hello');
    final port = await _reservePort();

    await service.start(
      settings: SimpleFileManagerSettings(
        enabled: true,
        rootPath: tempDir.path,
        port: port,
        bindAllInterfaces: false,
        favoritePaths: const <String>[],
      ),
    );

    final baseUrl = service.localUrl!;
    final treeResponse = await http.get(Uri.parse('$baseUrl/api/tree'));
    expect(treeResponse.statusCode, HttpStatus.ok);
    final treeJson = jsonDecode(treeResponse.body) as Map<String, dynamic>;
    final entries = treeJson['entries'] as List<dynamic>;
    expect(
      entries.any(
        (entry) =>
            (entry as Map<String, dynamic>)['name'] == 'notes' &&
            entry['type'] == 'directory',
      ),
      isTrue,
    );

    final fileResponse = await http.get(
      Uri.parse(
        '$baseUrl/api/file',
      ).replace(queryParameters: <String, String>{'path': file.path}),
    );
    expect(fileResponse.statusCode, HttpStatus.ok);
    expect(jsonDecode(fileResponse.body)['content'], '# Hello');

    final saveResponse = await http.post(
      Uri.parse('$baseUrl/api/file'),
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, String>{
        'path': file.path,
        'content': '# Updated',
      }),
    );
    expect(saveResponse.statusCode, HttpStatus.ok);
    expect(await file.readAsString(), '# Updated');
  });

  test('persists favorites and blocks paths outside root', () async {
    final file = File(p.join(tempDir.path, 'config.toml'));
    await file.writeAsString('title = "demo"');
    final outside = File(p.join(tempDir.parent.path, 'outside.txt'));
    await outside.writeAsString('outside');
    final port = await _reservePort();

    await service.start(
      settings: SimpleFileManagerSettings(
        enabled: true,
        rootPath: tempDir.path,
        port: port,
        bindAllInterfaces: false,
        favoritePaths: const <String>[],
      ),
    );

    final baseUrl = service.localUrl!;
    final addFavoriteResponse = await http.post(
      Uri.parse('$baseUrl/api/favorites'),
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, String>{'path': file.path}),
    );
    expect(addFavoriteResponse.statusCode, HttpStatus.ok);
    expect(
      jsonDecode(addFavoriteResponse.body)['favorites'],
      contains(file.path),
    );

    final blockedResponse = await http.get(
      Uri.parse(
        '$baseUrl/api/file',
      ).replace(queryParameters: <String, String>{'path': outside.path}),
    );
    expect(blockedResponse.statusCode, HttpStatus.forbidden);

    if (await outside.exists()) {
      await outside.delete();
    }
  });

  test('deletes files and removes deleted file from favorites', () async {
    final file = File(p.join(tempDir.path, 'delete-me.txt'));
    await file.writeAsString('delete me');
    final port = await _reservePort();

    await service.start(
      settings: SimpleFileManagerSettings(
        enabled: true,
        rootPath: tempDir.path,
        port: port,
        bindAllInterfaces: false,
        favoritePaths: <String>[file.path],
      ),
    );

    final baseUrl = service.localUrl!;
    final deleteResponse = await http.delete(
      Uri.parse(
        '$baseUrl/api/file',
      ).replace(queryParameters: <String, String>{'path': file.path}),
    );
    expect(deleteResponse.statusCode, HttpStatus.ok);
    expect(await file.exists(), isFalse);
    expect(
      jsonDecode(deleteResponse.body)['favorites'],
      isNot(contains(file.path)),
    );

    final readDeletedResponse = await http.get(
      Uri.parse(
        '$baseUrl/api/file',
      ).replace(queryParameters: <String, String>{'path': file.path}),
    );
    expect(readDeletedResponse.statusCode, HttpStatus.notFound);
  });

  test('serves editor page with mobile layout and save shortcut', () async {
    final port = await _reservePort();

    await service.start(
      settings: SimpleFileManagerSettings(
        enabled: true,
        rootPath: tempDir.path,
        port: port,
        bindAllInterfaces: false,
        favoritePaths: const <String>[],
      ),
    );

    final baseUrl = service.localUrl!;
    final pageResponse = await http.get(Uri.parse(baseUrl));

    expect(pageResponse.statusCode, HttpStatus.ok);
    expect(
      pageResponse.body,
      contains('grid-template-rows: minmax(260px, 40dvh) minmax(0, 1fr);'),
    );
    expect(pageResponse.body, contains("(e.ctrlKey || e.metaKey)"));
    expect(pageResponse.body, contains("e.key.toLowerCase() === 's'"));
  });

  test('records unexpected request failures through RuntimeLogger', () async {
    final port = await _reservePort();
    await service.start(
      settings: SimpleFileManagerSettings(
        enabled: true,
        rootPath: tempDir.path,
        port: port,
        bindAllInterfaces: false,
        favoritePaths: const <String>[],
      ),
    );

    final response = await http.post(
      Uri.parse('${service.localUrl}/api/file'),
      headers: <String, String>{'Content-Type': 'application/json'},
      body: '{',
    );

    expect(response.statusCode, HttpStatus.internalServerError);
    expect(runtimeLogger.messages, <String>[
      '[SimpleFileManager] Request handling failed',
    ]);
    expect(runtimeLogger.metadata.single, <String, Object?>{
      'method': 'POST',
      'path': '/api/file',
    });
  });
}

Future<int> _reservePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

class _FakeRuntimeLogger implements RuntimeLogger {
  final List<String> messages = <String>[];
  final List<Map<String, Object?>> metadata = <Map<String, Object?>>[];

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
    this.metadata.add(metadata ?? const <String, Object?>{});
  }

  @override
  Future<void> logFlutterError(FlutterErrorDetails details) async {}

  @override
  Future<void> logUnhandledError(Object error, StackTrace stackTrace) async {}
}
