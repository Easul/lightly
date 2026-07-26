import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/proxy/domain/proxy_core_config.dart';

void main() {
  test('VlessConfig preserves the native proxy JSON contract', () {
    final config = VlessConfig(
      uuid: 'test-uuid',
      serverAddr: 'edge.example.com',
      serverPort: 2083,
      security: 'tls',
      host: 'worker.example.com',
      sni: 'edge.example.com',
      path: '/speedtest',
      tlsInsecure: true,
    );

    expect(jsonDecode(config.toJson()), config.toMap());
    expect(config.toMap(), <String, dynamic>{
      'vless': <String, dynamic>{
        'uuid': 'test-uuid',
        'server_addr': 'edge.example.com',
        'server_port': 2083,
        'security': 'tls',
        'host': 'worker.example.com',
        'sni': 'edge.example.com',
        'path': '/speedtest',
        'tls_insecure': true,
      },
    });
  });

  test('Hysteria2Config preserves the native proxy JSON contract', () {
    final config = Hysteria2Config(
      serverAddr: 'hy2.example.com',
      serverPort: 8443,
      password: 'secret',
      sni: 'sni.example.com',
      obfs: 'salamander',
      obfsPassword: 'obfs-secret',
      tlsInsecure: true,
    );

    expect(jsonDecode(config.toJson()), config.toMap());
    expect(config.toMap(), <String, dynamic>{
      'hysteria2': <String, dynamic>{
        'server_addr': 'hy2.example.com',
        'server_port': 8443,
        'password': 'secret',
        'sni': 'sni.example.com',
        'obfs': 'salamander',
        'obfs_password': 'obfs-secret',
        'tls_insecure': true,
      },
    });
  });
}
