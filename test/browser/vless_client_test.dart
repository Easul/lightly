import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/vless_client.dart';

void main() {
  group('VlessConfig', () {
    test('parses basic vless URI', () {
      final config = VlessConfig.parse(
        'vless://a0b1c2d3-e4f5-6789-abcd-ef0123456789@example.com:443',
      );

      expect(config.uuid, 'a0b1c2d3-e4f5-6789-abcd-ef0123456789');
      expect(config.host, 'example.com');
      expect(config.port, 443);
      expect(config.sni, 'example.com');
      expect(config.tlsInsecure, isFalse);
    });

    test('parses vless URI with ws transport', () {
      final config = VlessConfig.parse(
        'vless://a0b1c2d3-e4f5-6789-abcd-ef0123456789@example.com:443?type=ws&path=/path&host=cdn.example.com&sni=real.example.com&insecure=1#Node',
      );

      expect(config.uuid, 'a0b1c2d3-e4f5-6789-abcd-ef0123456789');
      expect(config.host, 'example.com');
      expect(config.port, 443);
      expect(config.transportType, 'ws');
      expect(config.wsPath, '/path');
      expect(config.wsHost, 'cdn.example.com');
      expect(config.sni, 'real.example.com');
      expect(config.tlsInsecure, isTrue);
      expect(config.name, 'Node');
    });

    test('parses packetEncoding when present', () {
      final config = VlessConfig.parse(
        'vless://a0b1c2d3-e4f5-6789-abcd-ef0123456789@example.com:2095?type=ws&path=%2F&host=edge.example.com&packetEncoding=xudp',
      );

      expect(config.packetEncoding, 'xudp');
      expect(config.transportType, 'ws');
      expect(config.webSocketPath, '/');
    });

    test('prefers explicit sni for websocket tls and host for http header', () {
      final config = VlessConfig.parse(
        'vless://a0b1c2d3-e4f5-6789-abcd-ef0123456789@api.example.com:2083?type=ws&path=%2Fspeedtest&host=vc.example.com&sni=vc.example.com&security=tls',
      );

      expect(config.webSocketPath, '/speedtest');
      expect(config.webSocketTlsServerName, 'vc.example.com');
      expect(config.webSocketHttpHost, 'vc.example.com');
      expect(config.isTlsEnabled, isTrue);
    });

    test('keeps origin host as tls name when sni is absent', () {
      final config = VlessConfig.parse(
        'vless://a0b1c2d3-e4f5-6789-abcd-ef0123456789@example.com:2083?type=ws&host=cdn.example.com&path=%2F',
      );

      expect(config.webSocketTlsServerName, 'example.com');
      expect(config.webSocketHttpHost, 'cdn.example.com');
      expect(config.webSocketPath, '/');
    });

    test('throws on missing UUID', () {
      expect(
        () => VlessConfig.parse('vless://example.com:443'),
        throwsFormatException,
      );
    });

    test('throws on invalid scheme', () {
      expect(
        () => VlessConfig.parse(
          'trojan://a0b1c2d3-e4f5-6789-abcd-ef0123456789@example.com:443',
        ),
        throwsFormatException,
      );
    });
  });

  group('VLESS request header', () {
    test('builds correct header for IPv4', () {
      final header = buildVlessRequest(
        'a0b1c2d3-e4f5-6789-abcd-ef0123456789',
        '1.2.3.4',
        80,
      );

      expect(header[0], 0x00); // version
      expect(
        header.sublist(1, 17),
        uuidToBytes('a0b1c2d3-e4f5-6789-abcd-ef0123456789'),
      );
      expect(header[17], 0x00); // addons length
      expect(header[18], 0x01); // TCP command
      expect(header[19], 0x00); // port high
      expect(header[20], 0x50); // port low (80)
      expect(header[21], 0x01); // IPv4
      expect(header.sublist(22, 26), [1, 2, 3, 4]);
      expect(header.length, 26);
    });

    test('builds correct header for domain', () {
      final header = buildVlessRequest(
        'a0b1c2d3-e4f5-6789-abcd-ef0123456789',
        'example.com',
        443,
      );

      expect(header[0], 0x00); // version
      expect(header[17], 0x00); // addons length
      expect(header[18], 0x01); // TCP command
      expect(header[19], 0x01); // port high (443 >> 8 = 1)
      expect(header[20], 0xbb); // port low (443 & 0xff = 187)
      expect(header[21], 0x02); // Domain
      expect(header[22], 'example.com'.length);
      expect(
        header.sublist(23, 23 + 'example.com'.length),
        'example.com'.codeUnits,
      );
    });

    test('throws on invalid UUID', () {
      expect(
        () => buildVlessRequest('invalid-uuid', 'example.com', 443),
        throwsFormatException,
      );
    });
  });

  group('VLESS response header', () {
    test('strips response header from single frame', () {
      final buffered = BytesBuilder(copy: false);
      final result = consumeVlessResponseHeader(
        pending: true,
        buffered: buffered,
        chunk: [0x00, 0x00, 0x16, 0x03, 0x03],
      );

      expect(result.headerPending, isFalse);
      expect(result.payload, [0x16, 0x03, 0x03]);
    });

    test('waits for complete response header before yielding payload', () {
      final buffered = BytesBuilder(copy: false);
      final first = consumeVlessResponseHeader(
        pending: true,
        buffered: buffered,
        chunk: [0x00],
      );
      expect(first.headerPending, isTrue);
      expect(first.payload, isNull);

      final second = consumeVlessResponseHeader(
        pending: first.headerPending,
        buffered: buffered,
        chunk: [0x00, 0x16, 0x03, 0x03],
      );
      expect(second.headerPending, isFalse);
      expect(second.payload, [0x16, 0x03, 0x03]);
    });
  });

  group('preferred address selection', () {
    test('prefers ipv4 when both ipv6 and ipv4 exist', () {
      final selected = selectPreferredAddress([
        InternetAddress('2400:3200::1'),
        InternetAddress('1.2.3.4'),
      ]);

      expect(selected.address, '1.2.3.4');
      expect(selected.type, InternetAddressType.IPv4);
    });

    test('falls back to first address when ipv4 is absent', () {
      final selected = selectPreferredAddress([
        InternetAddress('2400:3200::1'),
        InternetAddress('2606:4700::1111'),
      ]);

      expect(selected.address, '2400:3200::1');
      expect(selected.type, InternetAddressType.IPv6);
    });

    test('orders ipv4 addresses before ipv6 addresses', () {
      final ordered = orderPreferredAddresses([
        InternetAddress('2400:3200::1'),
        InternetAddress('1.2.3.4'),
        InternetAddress('2606:4700::1111'),
        InternetAddress('5.6.7.8'),
      ]);

      expect(ordered.map((address) => address.address).toList(), [
        '1.2.3.4',
        '5.6.7.8',
        '2400:3200::1',
        '2606:4700::1111',
      ]);
    });
  });

  group('websocket host header', () {
    test('includes non-default TLS port in Host header', () {
      expect(
        buildWebSocketHostHeader(
          httpHost: 'vc.example.com',
          port: 2083,
          useTls: true,
        ),
        'vc.example.com:2083',
      );
    });

    test('keeps default TLS port out of Host header', () {
      expect(
        buildWebSocketHostHeader(
          httpHost: 'vc.example.com',
          port: 443,
          useTls: true,
        ),
        'vc.example.com',
      );
    });

    test('preserves explicit port in Host header', () {
      expect(
        buildWebSocketHostHeader(
          httpHost: '127.0.0.1:2095',
          port: 2095,
          useTls: false,
        ),
        '127.0.0.1:2095',
      );
    });

    test('adds brackets for ipv6 host when appending port', () {
      expect(
        buildWebSocketHostHeader(
          httpHost: '2606:4700::1111',
          port: 2095,
          useTls: false,
        ),
        '[2606:4700::1111]:2095',
      );
    });
  });

  group('websocket retryable errors', () {
    test('retries websocket upgrade on connection abort', () {
      final tunnel = VlessTunnel(
        VlessConfig(
          uuid: 'a0b1c2d3-e4f5-6789-abcd-ef0123456789',
          host: 'example.com',
          port: 443,
        ),
      );

      expect(
        tunnel.isRetryableWebSocketErrorForTest(
          const SocketException('Software caused connection abort'),
        ),
        isTrue,
      );
    });

    test('retries websocket upgrade on tunnel timeout', () {
      final tunnel = VlessTunnel(
        VlessConfig(
          uuid: 'a0b1c2d3-e4f5-6789-abcd-ef0123456789',
          host: 'example.com',
          port: 443,
        ),
      );

      expect(
        tunnel.isRetryableWebSocketErrorForTest(
          const SocketException('Timed out waiting for WebSocket upgrade'),
        ),
        isTrue,
      );
    });

    test('retries websocket upgrade on plain connection timeout', () {
      final tunnel = VlessTunnel(
        VlessConfig(
          uuid: 'a0b1c2d3-e4f5-6789-abcd-ef0123456789',
          host: 'example.com',
          port: 443,
        ),
      );

      expect(
        tunnel.isRetryableWebSocketErrorForTest(
          const SocketException('Connection timed out'),
        ),
        isTrue,
      );
    });
  });
}
