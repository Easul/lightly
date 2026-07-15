import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/services/browser_proxy_form_mutator.dart';
import 'package:lightly/browser/services/browser_settings_form_controller.dart';

void main() {
  group('BrowserProxyFormMutator', () {
    late BrowserSettingsFormController formController;
    const mutator = BrowserProxyFormMutator();

    setUp(() {
      formController = BrowserSettingsFormController();
    });

    tearDown(() {
      formController.dispose();
    });

    test('switching to vless clears host override and enables TLS', () {
      formController.proxyTransportHostController.text = 'old-host';
      formController.proxyTransportPathController.text = '/ws';

      mutator.changeProtocol(formController, BrowserProxyProtocol.vless);

      expect(formController.proxyTlsEnabled, isTrue);
      expect(formController.proxyTransportHostController.text, isEmpty);
      expect(formController.proxyTransportPathController.text, '/ws');
    });

    test('switching to hysteria2 clears VLESS transport fields', () {
      formController.proxyTransportPathController.text = '/ws';
      formController.proxyPacketEncoding = 'xudp';

      mutator.changeProtocol(formController, BrowserProxyProtocol.hysteria2);

      expect(formController.proxyTlsEnabled, isTrue);
      expect(formController.proxyTransportPathController.text, isEmpty);
      expect(formController.proxyPacketEncoding, isEmpty);
    });

    test('switching to http clears transport and TLS state', () {
      formController.selectedTransportType = 'ws';
      formController.proxyTransportHostController.text = 'host.example';
      formController.proxyServerNameController.text = 'sni.example';
      formController.proxyTlsEnabled = true;
      formController.proxyTlsInsecure = true;

      mutator.changeProtocol(formController, BrowserProxyProtocol.http);

      expect(formController.selectedTransportType, isEmpty);
      expect(formController.proxyTransportHostController.text, isEmpty);
      expect(formController.proxyServerNameController.text, isEmpty);
      expect(formController.proxyTlsEnabled, isFalse);
      expect(formController.proxyTlsInsecure, isFalse);
    });

    test('disabling TLS also clears insecure mode', () {
      formController.proxyTlsInsecure = true;

      mutator.setTlsEnabled(formController, false);

      expect(formController.proxyTlsEnabled, isFalse);
      expect(formController.proxyTlsInsecure, isFalse);
    });
  });
}
