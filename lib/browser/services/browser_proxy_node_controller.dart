import '../browser_settings.dart';
import 'browser_settings_form_controller.dart';

class BrowserProxyNodeController {
  BrowserProxyNodeController({
    required BrowserSettingsFormController formController,
    String Function()? createId,
  }) : _formController = formController,
       _createId =
           createId ?? (() => DateTime.now().microsecondsSinceEpoch.toString());

  final BrowserSettingsFormController _formController;
  final String Function() _createId;

  BrowserProxyNode buildNodeFromForm({
    required String id,
    required String name,
  }) {
    final settings = _formController.readFormData().toBrowserSettings();
    return BrowserProxyNode(
      id: id,
      name: name.trim().isEmpty ? defaultNodeName(settings) : name.trim(),
      proxyHost: settings.proxyHost,
      proxyPort: settings.proxyPort,
      proxyScheme: settings.proxyProtocol,
      proxyUuid: settings.proxyUuid,
      proxyTlsEnabled: settings.proxyTlsEnabled,
      proxyTlsInsecure: settings.proxyTlsInsecure,
      proxyServerName: settings.proxyServerName,
      proxyTransportType: settings.proxyTransportType,
      proxyTransportPath: settings.proxyTransportPath,
      proxyTransportHost: settings.proxyTransportHost,
      proxyPacketEncoding: settings.proxyPacketEncoding,
    );
  }

  String defaultNodeName(BrowserSettings settings) {
    final protocol = BrowserProxyProtocol.label(settings.proxyProtocol);
    final host = settings.proxyHost.trim();
    if (host.isEmpty) return '$protocol 节点';
    final port = settings.proxyPort?.toString();
    return port == null || port.isEmpty
        ? '$protocol $host'
        : '$protocol $host:$port';
  }

  void syncSelectedFromForm() {
    final selectedId = _formController.selectedProxyNodeId;
    if (selectedId == null) return;
    final index = _formController.proxyNodes.indexWhere(
      (node) => node.id == selectedId,
    );
    if (index < 0) return;
    final current = _formController.proxyNodes[index];
    final updated = buildNodeFromForm(id: current.id, name: current.name);
    _formController.proxyNodes = <BrowserProxyNode>[
      ..._formController.proxyNodes.take(index),
      updated,
      ..._formController.proxyNodes.skip(index + 1),
    ];
  }

  BrowserProxyNode? addCurrent({String? preferredName}) {
    final settings = buildSettings();
    if (settings.proxyHost.trim().isEmpty || settings.proxyPort == null) {
      return null;
    }
    final node = buildNodeFromForm(
      id: _createId(),
      name: preferredName ?? defaultNodeName(settings),
    );
    _formController.proxyNodes = <BrowserProxyNode>[
      ..._formController.proxyNodes,
      node,
    ];
    _formController.selectedProxyNodeId = node.id;
    return node;
  }

  bool select(String nodeId) {
    syncSelectedFromForm();
    BrowserProxyNode? selectedNode;
    for (final node in _formController.proxyNodes) {
      if (node.id == nodeId) {
        selectedNode = node;
        break;
      }
    }
    if (selectedNode == null) return false;
    _formController.selectedProxyNodeId = selectedNode.id;
    _formController.applyProxyNode(selectedNode);
    return true;
  }

  bool delete(String nodeId) {
    final existingNodes = _formController.proxyNodes;
    if (!existingNodes.any((node) => node.id == nodeId)) {
      return false;
    }
    final wasSelected = _formController.selectedProxyNodeId == nodeId;
    final nodes = existingNodes.where((node) => node.id != nodeId).toList();
    _formController.proxyNodes = nodes;
    if (wasSelected) {
      final next = nodes.isEmpty ? null : nodes.first;
      _formController.selectedProxyNodeId = next?.id;
      if (next != null) {
        _formController.applyProxyNode(next);
      }
    }
    return true;
  }

  BrowserProxyNode appendParsedSettings({
    required BrowserSettings settings,
    required String name,
  }) {
    final existingNodes = List<BrowserProxyNode>.from(
      _formController.proxyNodes,
    );
    _formController.applySettings(settings);
    final node = buildNodeFromForm(id: _createId(), name: name);
    _formController.proxyNodes = <BrowserProxyNode>[...existingNodes, node];
    _formController.selectedProxyNodeId = node.id;
    return node;
  }

  BrowserSettings buildSettings() {
    syncSelectedFromForm();
    return _formController.buildSettings();
  }
}
