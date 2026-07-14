import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/services/browser_proxy_node_controller.dart';
import 'package:lightly/browser/services/browser_settings_form_controller.dart';

void main() {
  group('BrowserProxyNodeController', () {
    late BrowserSettingsFormController formController;
    late BrowserProxyNodeController nodeController;
    var nextId = 0;

    setUp(() {
      nextId = 0;
      formController = BrowserSettingsFormController();
      nodeController = BrowserProxyNodeController(
        formController: formController,
        createId: () => 'node-${++nextId}',
      );
    });

    tearDown(() {
      formController.dispose();
    });

    test('adds a node from the current form with a stable default name', () {
      formController.applySettings(
        BrowserSettings.defaults().copyWith(
          proxyScheme: BrowserProxyProtocol.vless,
          proxyHost: 'edge.example.com',
          proxyPort: 443,
        ),
      );

      final node = nodeController.addCurrent();

      expect(node?.id, 'node-1');
      expect(node?.name, 'VLESS edge.example.com:443');
      expect(formController.proxyNodes, <BrowserProxyNode>[node!]);
      expect(formController.selectedProxyNodeId, node.id);
    });

    test('rejects adding a node without host and port', () {
      formController.applySettings(BrowserSettings.defaults());

      expect(nodeController.addCurrent(), isNull);
      expect(formController.proxyNodes, isEmpty);
    });

    test('syncs edited node fields before switching nodes', () {
      final first = _node(id: 'first', name: 'First', host: 'one.example.com');
      final second = _node(
        id: 'second',
        name: 'Second',
        host: 'two.example.com',
      );
      formController.applySettings(
        BrowserSettings.defaults().copyWith(
          proxyNodes: <BrowserProxyNode>[first, second],
          selectedProxyNodeId: first.id,
        ),
      );
      formController.applyProxyNode(first);
      formController.proxyHostController.text = 'edited.example.com';

      expect(nodeController.select(second.id), isTrue);

      expect(formController.proxyNodes.first.proxyHost, 'edited.example.com');
      expect(formController.selectedProxyNodeId, second.id);
      expect(formController.proxyHostController.text, 'two.example.com');
    });

    test('deleting the selected node selects the first remaining node', () {
      final first = _node(id: 'first', name: 'First', host: 'one.example.com');
      final second = _node(
        id: 'second',
        name: 'Second',
        host: 'two.example.com',
      );
      formController.applySettings(
        BrowserSettings.defaults().copyWith(
          proxyNodes: <BrowserProxyNode>[first, second],
          selectedProxyNodeId: second.id,
        ),
      );
      formController.applyProxyNode(second);

      expect(nodeController.delete(second.id), isTrue);

      expect(formController.proxyNodes, <BrowserProxyNode>[first]);
      expect(formController.selectedProxyNodeId, first.id);
      expect(formController.proxyHostController.text, 'one.example.com');
    });

    test('appends parsed settings without replacing existing nodes', () {
      final existing = _node(
        id: 'existing',
        name: 'Existing',
        host: 'old.example.com',
      );
      formController.applySettings(
        BrowserSettings.defaults().copyWith(
          proxyNodes: <BrowserProxyNode>[existing],
          selectedProxyNodeId: existing.id,
        ),
      );

      final appended = nodeController.appendParsedSettings(
        settings: BrowserSettings.defaults().copyWith(
          proxyScheme: BrowserProxyProtocol.vless,
          proxyHost: 'new.example.com',
          proxyPort: 443,
        ),
        name: 'New',
      );

      expect(formController.proxyNodes, <BrowserProxyNode>[existing, appended]);
      expect(formController.selectedProxyNodeId, appended.id);
      expect(formController.proxyHostController.text, 'new.example.com');
    });
  });
}

BrowserProxyNode _node({
  required String id,
  required String name,
  required String host,
}) {
  return BrowserProxyNode(
    id: id,
    name: name,
    proxyHost: host,
    proxyPort: 443,
    proxyScheme: BrowserProxyProtocol.vless,
    proxyUuid: 'uuid',
    proxyTlsEnabled: true,
    proxyTlsInsecure: false,
    proxyServerName: host,
    proxyTransportType: 'ws',
    proxyTransportPath: '/',
    proxyTransportHost: host,
    proxyPacketEncoding: '',
  );
}
