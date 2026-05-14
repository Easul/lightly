import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/models/browser_subscription_node.dart';
import 'package:lightly/browser/services/browser_subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BrowserSubscriptionNode', () {
    test('serializes and restores json', () {
      const node = BrowserSubscriptionNode(
        id: 'node-1',
        protocol: BrowserProxyProtocol.vless,
        host: 'node.example.com',
        port: 443,
        name: 'Example Node',
        rawUrl: 'vless://example',
        settings: <String, dynamic>{'uuid': 'abc', 'tlsEnabled': true},
      );

      final restored = BrowserSubscriptionNode.fromJson(node.toJson());

      expect(restored.id, 'node-1');
      expect(restored.protocol, BrowserProxyProtocol.vless);
      expect(restored.host, 'node.example.com');
      expect(restored.port, 443);
      expect(restored.name, 'Example Node');
      expect(restored.rawUrl, 'vless://example');
      expect(restored.settings['uuid'], 'abc');
      expect(restored.settings['tlsEnabled'], isTrue);
    });

    test('normalizes unknown protocol to http on restore', () {
      final json = <String, dynamic>{
        'id': 'node-2',
        'protocol': 'vmess',
        'host': 'vmess.example.com',
        'port': 443,
        'name': 'VMess Node',
        'rawUrl': 'vmess://example',
        'settings': <String, dynamic>{},
      };

      final restored = BrowserSubscriptionNode.fromJson(json);

      expect(restored.protocol, BrowserProxyProtocol.http);
    });
  });

  group('BrowserSubscriptionService', () {
    late BrowserSubscriptionService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = BrowserSubscriptionService();
    });

    test('fetchSubscription returns response body', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        expect(request.uri.path, '/subscription');
        request.response.write('http://127.0.0.1:1080#Local');
        await request.response.close();
      });

      final body = await service.fetchSubscription(
        'http://${server.address.host}:${server.port}/subscription',
      );

      expect(body, 'http://127.0.0.1:1080#Local');
    });

    test('parseNodes handles vless and http lines', () {
      final nodes = service.parseNodes('''
invalid line
# comment line
vless://a0b1c2d3-e4f5-6789-abcd-ef0123456789@vless.example.com:443?sni=vless-sni.example.com&type=ws&host=cdn.vless.example.com&path=%2Fvless#VLESS%20Node
http://demo:pass@http.example.com:1080#Http%20Node
https://127.0.0.1:1080#Direct
trojan://ignored
''');

      expect(nodes, hasLength(3));

      expect(nodes[0].protocol, BrowserProxyProtocol.vless);
      expect(nodes[0].name, 'VLESS Node');
      expect(nodes[0].host, 'vless.example.com');
      expect(nodes[0].port, 443);
      expect(nodes[0].settings['uuid'], 'a0b1c2d3-e4f5-6789-abcd-ef0123456789');
      expect(nodes[0].settings['serverName'], 'vless-sni.example.com');
      expect(nodes[0].settings['transportType'], 'ws');
      expect(nodes[0].settings['transportPath'], '/vless');
      expect(nodes[0].settings['transportHost'], 'cdn.vless.example.com');
      expect(nodes[0].settings['tlsEnabled'], isTrue);

      expect(nodes[1].protocol, BrowserProxyProtocol.http);
      expect(nodes[1].host, 'http.example.com');
      expect(nodes[1].port, 1080);
      expect(nodes[1].settings['password'], 'pass');

      expect(nodes[2].protocol, BrowserProxyProtocol.http);
      expect(nodes[2].host, '127.0.0.1');
      expect(nodes[2].port, 1080);
      expect(nodes[2].name, 'Direct');
    });

    test('parseNodes decodes base64 subscription content', () {
      const plainText = 'http://127.0.0.1:1080#Local\n';
      final encoded = base64Encode(utf8.encode(plainText));

      final nodes = service.parseNodes(encoded);

      expect(nodes, hasLength(1));
      expect(nodes.single.protocol, BrowserProxyProtocol.http);
      expect(nodes.single.name, 'Local');
    });

    test('storeNodes and getNodes persist parsed nodes', () async {
      final nodes = service.parseNodes('http://127.0.0.1:1080#Local');

      await service.storeNodes(nodes);
      final restored = await service.getNodes();

      expect(restored, hasLength(1));
      expect(restored.single.id, nodes.single.id);
      expect(restored.single.rawUrl, nodes.single.rawUrl);
    });

    test('getNodes normalizes unsupported legacy protocols to http', () async {
      final nodes = service.parseNodes('''
vless://uuid@v.example.com:443#VLESS
http://127.0.0.1:1080#Http
''');
      await service.storeNodes(nodes);

      // Simulate legacy stored nodes by injecting raw JSON
      final prefs = await SharedPreferences.getInstance();
      final rawNodes = [
        nodes[0].toJson(),
        nodes[1].toJson(),
        {
          'id': 'legacy-vmess',
          'protocol': 'vmess',
          'host': 'v.example.com',
          'port': 443,
          'name': 'Legacy VMess',
          'rawUrl': 'vmess://legacy',
          'settings': <String, dynamic>{},
        },
      ];
      await prefs.setString('browser_subscription_nodes', jsonEncode(rawNodes));

      final restored = await service.getNodes();

      // Legacy protocols are now filtered out before normalization
      expect(restored, hasLength(2));
      expect(restored.any((n) => n.id == 'legacy-vmess'), isFalse);
    });

    test(
      'selectNode returns BrowserSettings patch for chosen http node',
      () async {
        final nodes = service.parseNodes(
          'http://demo:pass@http.example.com:1080#Http%20Node',
        );
        await service.storeNodes(nodes);

        final patch = await service.selectNode(nodes.single.id);

        expect(patch.proxyEnabled, isTrue);
        expect(patch.proxyScheme, BrowserProxyProtocol.http);
        expect(patch.proxyHost, 'http.example.com');
        expect(patch.proxyPort, 1080);
        expect(patch.proxyUuid, 'pass');
        expect(patch.proxyValidationError, isNull);
      },
    );

    test('convertNodeToSettings maps vless nodes', () {
      final node = service
          .parseNodes(
            'vless://a0b1c2d3-e4f5-6789-abcd-ef0123456789@v.example.com:443?sni=v.sni.com#VLESS',
          )
          .single;

      final patch = service.convertNodeToSettings(node);

      expect(patch.proxyScheme, BrowserProxyProtocol.vless);
      expect(patch.proxyHost, 'v.example.com');
      expect(patch.proxyPort, 443);
      expect(patch.proxyUuid, 'a0b1c2d3-e4f5-6789-abcd-ef0123456789');
      expect(patch.proxyTlsEnabled, isTrue);
      expect(patch.proxyServerName, 'v.sni.com');
      expect(patch.proxyValidationError, isNull);
    });

    test('convertNodeToSettings preserves tls for non-443 ws vless node', () {
      final node = service
          .parseNodes(
            'vless://86c50e3a-5b87-49dd-bd20-03c7f2735e40@api.example.com:2083/?type=ws&encryption=none&flow=&host=vc.example.com&path=%2Fspeedtest&security=tls&sni=vc.example.com#vless-ws-tls',
          )
          .single;

      final patch = service.convertNodeToSettings(node);

      expect(node.settings['tlsEnabled'], isTrue);
      expect(node.settings['transportType'], 'ws');
      expect(node.settings['transportPath'], '/speedtest');
      expect(node.settings['transportHost'], 'vc.example.com');
      expect(node.settings['serverName'], 'vc.example.com');
      expect(patch.proxyTlsEnabled, isTrue);
      expect(patch.proxyTransportType, 'ws');
      expect(patch.proxyTransportPath, '/speedtest');
      expect(patch.proxyTransportHost, 'vc.example.com');
      expect(patch.proxyServerName, 'vc.example.com');
    });

    test('convertNodeToSettings preserves security none for vless node', () {
      final node = service
          .parseNodes(
            'vless://86c50e3a-5b87-49dd-bd20-03c7f2735e40@example.com:80/?type=ws&security=none&host=edge.example.com&path=%2F#plain-vless',
          )
          .single;

      final patch = service.convertNodeToSettings(node);

      expect(node.settings['tlsEnabled'], isFalse);
      expect(patch.proxyTlsEnabled, isFalse);
    });

    test('convertNodeToSettings preserves packetEncoding for vless node', () {
      final node = service
          .parseNodes(
            'vless://86c50e3a-5b87-49dd-bd20-03c7f2735e40@example.com:2095/?type=ws&security=none&host=edge.example.com&path=%2F&packetEncoding=xudp#xudp-vless',
          )
          .single;

      final patch = service.convertNodeToSettings(node);

      expect(node.settings['packetEncoding'], 'xudp');
      expect(patch.proxyPacketEncoding, 'xudp');
    });

    test('convertNodeToSettings maps http nodes', () {
      final node = service
          .parseNodes('http://user:pass@http.example.com:1080#Http')
          .single;

      final patch = service.convertNodeToSettings(node);

      expect(patch.proxyScheme, BrowserProxyProtocol.http);
      expect(patch.proxyHost, 'http.example.com');
      expect(patch.proxyPort, 1080);
      expect(patch.proxyUuid, 'pass');
      expect(patch.proxyValidationError, isNull);
    });
  });
}
