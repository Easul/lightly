import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/local_sharing/local_http/local_http_file_server_service.dart';
import 'package:lightly/features/local_sharing/local_http/local_http_server_config.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late LocalHttpFileServerService service;

  setUp(() async {
    HttpOverrides.global = null;
    tempDirectory = await Directory.systemTemp.createTemp('local_http_');
    service = LocalHttpFileServerService();
    await service.stop();
  });

  tearDown(() async {
    await service.stop();
    await tempDirectory.delete(recursive: true);
  });

  test('applies local config and serves files from its root', () async {
    await File(p.join(tempDirectory.path, 'hello.txt')).writeAsString('hello');
    final port = await _reservePort();

    await service.applySettings(
      LocalHttpServerConfig(
        enabled: true,
        rootPath: tempDirectory.path,
        port: port,
        bindAllInterfaces: false,
        uploadKey: 'secret',
      ),
    );

    final client = HttpClient();
    try {
      final response = await client.getUrl(
        Uri.parse('${service.getServerAddress()}/hello.txt'),
      );
      final opened = await response.close();
      expect(opened.statusCode, HttpStatus.ok);
      expect(await utf8.decoder.bind(opened).join(), 'hello');
      expect(service.rootPath, tempDirectory.path);
      expect(service.validateUploadKey('secret'), isTrue);
      expect(service.validateUploadKey('wrong'), isFalse);
    } finally {
      client.close(force: true);
    }
  });

  test('disabled config stops the running server', () async {
    await service.start(rootPath: tempDirectory.path);
    expect(service.isRunning, isTrue);

    await service.applySettings(
      LocalHttpServerConfig(
        enabled: false,
        rootPath: tempDirectory.path,
        port: null,
        bindAllInterfaces: false,
        uploadKey: '',
      ),
    );

    expect(service.isRunning, isFalse);
  });

  test('config validates root and port without BrowserSettings', () {
    expect(
      const LocalHttpServerConfig(
        enabled: true,
        rootPath: '',
        port: 70000,
        bindAllInterfaces: false,
        uploadKey: '',
      ).validationError,
      '本地 HTTP 服务目录不能为空',
    );
    expect(
      const LocalHttpServerConfig(
        enabled: true,
        rootPath: '/tmp',
        port: 70000,
        bindAllInterfaces: false,
        uploadKey: '',
      ).validationError,
      '本地 HTTP 服务端口必须是 1-65535',
    );
  });
}

Future<int> _reservePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
