import 'dart:convert';

class VlessConfig {
  VlessConfig({
    required this.uuid,
    required this.serverAddr,
    this.serverPort = 443,
    this.security = 'tls',
    this.host,
    this.sni,
    this.path = '/',
    this.tlsInsecure = false,
  });

  final String uuid;
  final String serverAddr;
  final int serverPort;
  final String security;
  final String? host;
  final String? sni;
  final String path;
  final bool tlsInsecure;

  Map<String, dynamic> toMap() {
    return {
      'vless': {
        'uuid': uuid,
        'server_addr': serverAddr,
        'server_port': serverPort,
        'security': security,
        'host': host,
        'sni': sni,
        'path': path,
        'tls_insecure': tlsInsecure,
      },
    };
  }

  String toJson() => jsonEncode(toMap());
}

class Hysteria2Config {
  Hysteria2Config({
    required this.serverAddr,
    this.serverPort = 443,
    required this.password,
    this.sni,
    this.obfs,
    this.obfsPassword,
    this.tlsInsecure = false,
  });

  final String serverAddr;
  final int serverPort;
  final String password;
  final String? sni;
  final String? obfs;
  final String? obfsPassword;
  final bool tlsInsecure;

  Map<String, dynamic> toMap() {
    return {
      'hysteria2': {
        'server_addr': serverAddr,
        'server_port': serverPort,
        'password': password,
        'sni': sni,
        'obfs': obfs,
        'obfs_password': obfsPassword,
        'tls_insecure': tlsInsecure,
      },
    };
  }

  String toJson() => jsonEncode(toMap());
}
