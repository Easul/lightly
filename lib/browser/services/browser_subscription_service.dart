import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../browser_settings.dart';
import '../models/browser_subscription_node.dart';

class BrowserSubscriptionService {
  BrowserSubscriptionService({HttpClient Function()? httpClientFactory})
    : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static const String defaultSubscriptionUrl =
      'https://www.xrayvip.com/free.txt';
  static const String _storageKey = 'browser_subscription_nodes';
  static const String _selectedNodeKey = 'browser_subscription_selected_node';

  final HttpClient Function() _httpClientFactory;

  Future<String> fetchSubscription([
    String url = defaultSubscriptionUrl,
  ]) async {
    final client = _httpClientFactory();
    final uri = Uri.parse(url);

    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      );
      request.headers.set('Accept', '*/*');
      request.headers.set('Connection', 'keep-alive');

      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Subscription request failed with ${response.statusCode}',
          uri: uri,
        );
      }

      final bodyBytes = <int>[];
      await for (final chunk in response) {
        bodyBytes.addAll(chunk);
      }

      return utf8.decode(bodyBytes);
    } on FormatException catch (e) {
      throw HttpException('Failed to decode subscription data: $e', uri: uri);
    } on HttpException {
      rethrow;
    } on Exception catch (e) {
      throw HttpException('Network error: $e', uri: uri);
    } finally {
      client.close(force: true);
    }
  }

  List<BrowserSubscriptionNode> parseNodes(String text) {
    final sourceText = _normalizeSubscriptionText(text);
    final nodes = <BrowserSubscriptionNode>[];

    for (final rawLine in const LineSplitter().convert(sourceText)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }

      final node = _parseNode(line);
      if (node != null) {
        nodes.add(node);
      }
    }

    return nodes;
  }

  Future<void> storeNodes(List<BrowserSubscriptionNode> nodes) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = jsonEncode(nodes.map((node) => node.toJson()).toList());
    await preferences.setString(_storageKey, encoded);

    final selectedNodeId = preferences.getString(_selectedNodeKey);
    final selectionStillExists = nodes.any((node) => node.id == selectedNodeId);
    if (!selectionStillExists) {
      await preferences.remove(_selectedNodeKey);
    }
  }

  Future<List<BrowserSubscriptionNode>> getNodes() async {
    final preferences = await SharedPreferences.getInstance();
    final storedValue = preferences.getString(_storageKey);

    if (storedValue == null || storedValue.isEmpty) {
      return const <BrowserSubscriptionNode>[];
    }

    final decoded = jsonDecode(storedValue) as List<dynamic>;
    final rawItems = decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    // Filter out unsupported legacy protocols using the raw stored value
    // before normalization converts them to http.
    final supportedItems = rawItems.where((item) {
      final rawProtocol = (item['protocol'] as String? ?? '').toLowerCase();
      return rawProtocol == BrowserProxyProtocol.http ||
          rawProtocol == BrowserProxyProtocol.vless ||
          rawProtocol == BrowserProxyProtocol.hysteria2 ||
          rawProtocol == 'hy2';
    });

    return supportedItems.map(BrowserSubscriptionNode.fromJson).toList();
  }

  Future<BrowserSettings> selectNode(
    String id, {
    BrowserSettings? currentSettings,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final nodes = await getNodes();

    BrowserSubscriptionNode? selectedNode;
    for (final node in nodes) {
      if (node.id == id) {
        selectedNode = node;
        break;
      }
    }

    if (selectedNode == null) {
      throw StateError('Subscription node not found: $id');
    }

    await preferences.setString(_selectedNodeKey, id);
    return convertNodeToSettings(
      selectedNode,
      currentSettings: currentSettings,
    );
  }

  BrowserSettings convertNodeToSettings(
    BrowserSubscriptionNode node, {
    BrowserSettings? currentSettings,
  }) {
    final settings = node.settings;
    final protocol = BrowserProxyProtocol.normalize(node.protocol);
    final tlsEnabled = _readBool(settings['tlsEnabled']);

    final baseSettings = currentSettings ?? BrowserSettings.defaults();

    return baseSettings.copyWith(
      proxyEnabled: true,
      proxyHost: node.host,
      proxyPort: node.port,
      proxyScheme: protocol,
      proxyUuid: protocol == BrowserProxyProtocol.vless
          ? _readString(settings['uuid'])
          : _readString(settings['password']),
      proxyTlsEnabled: tlsEnabled,
      proxyTlsInsecure: _readBool(settings['tlsInsecure']),
      proxyServerName: _readString(settings['serverName']),
      proxyTransportType: _readString(settings['transportType']),
      proxyTransportPath: _readString(settings['transportPath']),
      proxyTransportHost: _readString(settings['transportHost']),
      proxyPacketEncoding: _readString(settings['packetEncoding']),
    );
  }

  BrowserSubscriptionNode? parseSingleNode(String rawUrl) {
    return _parseNode(rawUrl.trim());
  }

  BrowserSubscriptionNode? _parseNode(String rawUrl) {
    final schemeMatch = RegExp(r'^([a-zA-Z0-9+.-]+)://').firstMatch(rawUrl);
    if (schemeMatch == null) {
      return null;
    }

    final scheme = schemeMatch.group(1)?.toLowerCase() ?? '';
    switch (scheme) {
      case 'vless':
        return _parseVless(rawUrl);
      case 'hy2':
      case 'hysteria2':
        return _parseHysteria2(rawUrl);
      case 'http':
      case 'https':
        return _parseHttp(rawUrl);
      default:
        return null;
    }
  }

  BrowserSubscriptionNode? _parseVless(String rawUrl) {
    final uri = _tryParseUri(rawUrl);
    if (uri == null || uri.host.isEmpty || uri.port <= 0) {
      return null;
    }

    final query = uri.queryParameters;
    // security 参数：显式设置则用之，未设置则按端口推断（443默认tls）
    final hasExplicitSecurity = query.containsKey('security');
    final tlsMode = hasExplicitSecurity
        ? _stringFromQuery(query, 'security', fallback: '')
        : (uri.port == 443 ? 'tls' : '');
    return BrowserSubscriptionNode(
      id: _buildNodeId(rawUrl),
      protocol: BrowserProxyProtocol.vless,
      host: uri.host,
      port: uri.port,
      name: _buildName(
        protocol: BrowserProxyProtocol.vless,
        host: uri.host,
        port: uri.port,
        preferredName: _decodeName(uri.fragment),
      ),
      rawUrl: rawUrl,
      settings: <String, dynamic>{
        'uuid': _decodeUserInfoPart(uri.userInfo, 0),
        'tlsEnabled': _hasTlsValue(tlsMode),
        'tlsInsecure': _queryBool(query, const ['allowInsecure', 'insecure']),
        'serverName': _stringFromQuery(query, 'sni', fallback: uri.host),
        'transportType': _stringFromQuery(query, 'type'),
        'transportPath': _stringFromQuery(query, 'path'),
        'transportHost': _stringFromQuery(query, 'host'),
        'packetEncoding': _stringFromQuery(query, 'packetEncoding'),
        'encryption': _stringFromQuery(query, 'encryption'),
        'flow': _stringFromQuery(query, 'flow'),
      },
    );
  }

  BrowserSubscriptionNode? _parseHttp(String rawUrl) {
    final uri = _tryParseUri(rawUrl);
    if (uri == null || uri.host.isEmpty || uri.port <= 0) {
      return null;
    }

    return BrowserSubscriptionNode(
      id: _buildNodeId(rawUrl),
      protocol: BrowserProxyProtocol.http,
      host: uri.host,
      port: uri.port,
      name: _buildName(
        protocol: BrowserProxyProtocol.http,
        host: uri.host,
        port: uri.port,
        preferredName: _decodeName(uri.fragment),
      ),
      rawUrl: rawUrl,
      settings: <String, dynamic>{
        'password': _decodeUserInfoPart(uri.userInfo, 1),
      },
    );
  }

  BrowserSubscriptionNode? _parseHysteria2(String rawUrl) {
    final uri = _tryParseUri(rawUrl);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }

    final query = uri.queryParameters;
    final port = uri.port > 0 ? uri.port : 443;
    return BrowserSubscriptionNode(
      id: _buildNodeId(rawUrl),
      protocol: BrowserProxyProtocol.hysteria2,
      host: uri.host,
      port: port,
      name: _buildName(
        protocol: BrowserProxyProtocol.hysteria2,
        host: uri.host,
        port: port,
        preferredName: _decodeName(uri.fragment),
      ),
      rawUrl: rawUrl,
      settings: <String, dynamic>{
        'password': _decodeUserInfoPart(uri.userInfo, 0),
        'tlsEnabled': true,
        'tlsInsecure': _queryBool(query, const ['allowInsecure', 'insecure']),
        'serverName': _stringFromQuery(query, 'sni', fallback: uri.host),
        'transportType': _stringFromQuery(query, 'obfs'),
        'transportHost': _stringFromQuery(query, 'obfs-password'),
      },
    );
  }

  String _normalizeSubscriptionText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final collapsed = trimmed.replaceAll(RegExp(r'\s+'), '');
    if (collapsed.contains('://')) {
      return text;
    }

    final decoded = _tryDecodeBase64ToUtf8(collapsed);
    if (decoded != null && decoded.contains('://')) {
      return decoded;
    }

    return text;
  }

  Uri? _tryParseUri(String value) {
    try {
      return Uri.parse(value);
    } catch (_) {
      return null;
    }
  }

  String _buildName({
    required String protocol,
    required String host,
    required int port,
    required String preferredName,
  }) {
    if (preferredName.trim().isNotEmpty) {
      return preferredName.trim();
    }

    return '${BrowserProxyProtocol.label(protocol)} $host:$port';
  }

  String _buildNodeId(String rawUrl) {
    var hash = 0xcbf29ce484222325;
    for (final codeUnit in utf8.encode(rawUrl)) {
      hash ^= codeUnit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16);
  }

  String _decodeUserInfoPart(String userInfo, int index) {
    if (userInfo.isEmpty) {
      return '';
    }

    final separatorIndex = userInfo.indexOf(':');
    if (separatorIndex < 0) {
      return index == 0 ? Uri.decodeComponent(userInfo) : '';
    }

    if (index == 0) {
      return Uri.decodeComponent(userInfo.substring(0, separatorIndex));
    }

    if (index == 1) {
      return Uri.decodeComponent(userInfo.substring(separatorIndex + 1));
    }

    return '';
  }

  String _decodeName(String value) {
    if (value.isEmpty) {
      return '';
    }

    try {
      return Uri.decodeComponent(value).trim();
    } catch (_) {
      return value.trim();
    }
  }

  String _stringFromQuery(
    Map<String, String> query,
    String key, {
    String fallback = '',
  }) {
    final value = query[key];
    if (value == null || value.trim().isEmpty) {
      return fallback;
    }
    return value.trim();
  }

  bool _queryBool(Map<String, String> query, List<String> keys) {
    for (final key in keys) {
      final value = query[key];
      if (value == null) {
        continue;
      }

      final normalized = value.trim().toLowerCase();
      if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
        return true;
      }
      if (normalized == '0' || normalized == 'false' || normalized == 'no') {
        return false;
      }
    }
    return false;
  }

  bool _hasTlsValue(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'none') {
      return false;
    }
    return normalized != 'false';
  }

  String _readString(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  bool _readBool(Object? value) {
    if (value is bool) {
      return value;
    }
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  String? _tryDecodeBase64ToUtf8(String value) {
    if (value.trim().isEmpty) {
      return null;
    }

    final normalized = value.trim().replaceAll('-', '+').replaceAll('_', '/');
    final remainder = normalized.length % 4;
    final padded = remainder == 0
        ? normalized
        : '$normalized${'=' * (4 - remainder)}';

    try {
      return utf8.decode(base64Decode(padded));
    } catch (_) {
      return null;
    }
  }
}
