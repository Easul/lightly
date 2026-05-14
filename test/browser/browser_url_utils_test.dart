import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/utils/browser_url_utils.dart';

void main() {
  group('normalizeBrowserUrl', () {
    test('adds https scheme for direct host input', () {
      expect(
        normalizeBrowserUrl('example.com/path?q=1'),
        'https://example.com/path?q=1',
      );
    });

    test('uses http scheme for private ipv4 and localhost targets', () {
      expect(normalizeBrowserUrl('10.1.2.3'), 'http://10.1.2.3');
      expect(
        normalizeBrowserUrl('192.168.1.8:8080'),
        'http://192.168.1.8:8080',
      );
      expect(
        normalizeBrowserUrl('172.16.0.5/admin'),
        'http://172.16.0.5/admin',
      );
      expect(normalizeBrowserUrl('127.0.0.1:3000'), 'http://127.0.0.1:3000');
      expect(normalizeBrowserUrl('localhost:3000'), 'http://localhost:3000');
    });

    test('keeps https default for public ipv4 addresses', () {
      expect(normalizeBrowserUrl('8.8.8.8'), 'https://8.8.8.8');
    });

    test('keeps valid file url', () {
      expect(
        normalizeBrowserUrl('file:///storage/emulated/0/test.txt'),
        'file:///storage/emulated/0/test.txt',
      );
    });

    test('keeps valid file url with spaces and chinese characters', () {
      expect(
        normalizeBrowserUrl('file:///storage/emulated/0/Download/测试 页面.html'),
        'file:///storage/emulated/0/Download/%E6%B5%8B%E8%AF%95%20%E9%A1%B5%E9%9D%A2.html',
      );
    });

    test('normalizes common android file url missing third slash', () {
      expect(
        normalizeBrowserUrl('file://storage/emulated/0/Download/index.html'),
        'file:///storage/emulated/0/Download/index.html',
      );
    });

    test('rejects inputs with spaces or chinese characters', () {
      expect(normalizeBrowserUrl('hello world'), isNull);
      expect(normalizeBrowserUrl('示例.com'), isNull);
    });

    test('rejects unsupported schemes and non host search text', () {
      expect(normalizeBrowserUrl('javascript:alert(1)'), isNull);
      expect(normalizeBrowserUrl('example'), isNull);
    });
  });

  group('isDirectHostInput', () {
    test('accepts localhost ipv4 and dotted hosts', () {
      expect(isDirectHostInput('localhost'), isTrue);
      expect(isDirectHostInput('127.0.0.1'), isTrue);
      expect(isDirectHostInput('sub.example.com'), isTrue);
    });

    test('rejects blank and undotted hostnames', () {
      expect(isDirectHostInput(''), isFalse);
      expect(isDirectHostInput('example'), isFalse);
    });
  });
}
