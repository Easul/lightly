import '../browser_settings.dart';

class BrowserSubscriptionNode {
  const BrowserSubscriptionNode({
    required this.id,
    required this.protocol,
    required this.host,
    required this.port,
    required this.name,
    required this.rawUrl,
    required this.settings,
  });

  final String id;
  final String protocol;
  final String host;
  final int port;
  final String name;
  final String rawUrl;
  final Map<String, dynamic> settings;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'protocol': protocol,
      'host': host,
      'port': port,
      'name': name,
      'rawUrl': rawUrl,
      'settings': settings,
    };
  }

  factory BrowserSubscriptionNode.fromJson(Map<String, dynamic> json) {
    return BrowserSubscriptionNode(
      id: json['id'] as String? ?? '',
      protocol: BrowserProxyProtocol.normalize(json['protocol'] as String?),
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      rawUrl: json['rawUrl'] as String? ?? '',
      settings: Map<String, dynamic>.from(
        json['settings'] as Map? ?? const <String, dynamic>{},
      ),
    );
  }
}
