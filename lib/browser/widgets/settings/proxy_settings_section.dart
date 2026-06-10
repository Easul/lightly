import 'package:flutter/material.dart';

import '../../browser_settings.dart';
import 'settings_section_widgets.dart';

part 'proxy_settings_section_parts.dart';

class ProxySettingsSection extends StatelessWidget {
  const ProxySettingsSection({
    super.key,
    required this.enabled,
    required this.supported,
    required this.isSaving,
    required this.stateLabel,
    required this.stateColor,
    required this.detailText,
    required this.nodeLinkController,
    required this.proxyNodes,
    required this.selectedProxyNodeId,
    required this.errorMessage,
    required this.selectedProtocol,
    required this.showsUuidField,
    required this.showsTransportFields,
    required this.showsHysteria2ObfsFields,
    required this.showsPacketEncodingField,
    required this.showsTlsFields,
    required this.proxyTlsEnabled,
    required this.selectedTransportType,
    required this.proxyPacketEncoding,
    required this.proxyTlsInsecure,
    required this.proxyHostController,
    required this.proxyPortController,
    required this.localProxyPortController,
    required this.proxyUuidController,
    required this.proxyServerNameController,
    required this.proxyTransportPathController,
    required this.proxyTransportHostController,
    required this.proxyBypassDomainsController,
    required this.onToggle,
    required this.onParse,
    required this.onTestSpeed,
    required this.onAddProxyNode,
    required this.onSelectProxyNode,
    required this.onDeleteProxyNode,
    required this.onConfigurationChanged,
    required this.onProtocolChanged,
    required this.onTlsEnabledChanged,
    required this.onTransportTypeChanged,
    required this.onPacketEncodingChanged,
    required this.onTlsInsecureChanged,
  });

  final bool enabled;
  final bool supported;
  final bool isSaving;
  final String stateLabel;
  final Color stateColor;
  final String detailText;
  final TextEditingController nodeLinkController;
  final List<BrowserProxyNode> proxyNodes;
  final String? selectedProxyNodeId;
  final String? errorMessage;
  final String selectedProtocol;
  final bool showsUuidField;
  final bool showsTransportFields;
  final bool showsHysteria2ObfsFields;
  final bool showsPacketEncodingField;
  final bool showsTlsFields;
  final bool proxyTlsEnabled;
  final String selectedTransportType;
  final String proxyPacketEncoding;
  final bool proxyTlsInsecure;
  final TextEditingController proxyHostController;
  final TextEditingController proxyPortController;
  final TextEditingController localProxyPortController;
  final TextEditingController proxyUuidController;
  final TextEditingController proxyServerNameController;
  final TextEditingController proxyTransportPathController;
  final TextEditingController proxyTransportHostController;
  final TextEditingController proxyBypassDomainsController;
  final ValueChanged<bool> onToggle;
  final Future<void> Function() onParse;
  final Future<void> Function() onTestSpeed;
  final VoidCallback onAddProxyNode;
  final ValueChanged<String> onSelectProxyNode;
  final ValueChanged<String> onDeleteProxyNode;
  final VoidCallback onConfigurationChanged;
  final ValueChanged<String> onProtocolChanged;
  final ValueChanged<bool> onTlsEnabledChanged;
  final ValueChanged<String> onTransportTypeChanged;
  final ValueChanged<String> onPacketEncodingChanged;
  final ValueChanged<bool> onTlsInsecureChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProxyStatusCard(
          enabled: enabled,
          supported: supported,
          isSaving: isSaving,
          stateLabel: stateLabel,
          stateColor: stateColor,
          detailText: detailText,
          onToggle: onToggle,
        ),
        const SizedBox(height: 16),
        _NodeLinkParserCard(
          nodeLinkController: nodeLinkController,
          isSaving: isSaving,
          errorMessage: errorMessage,
          onParse: onParse,
          onTestSpeed: onTestSpeed,
        ),
        const SizedBox(height: 16),
        _ProxyNodeListCard(
          nodes: proxyNodes,
          selectedNodeId: selectedProxyNodeId,
          onAddProxyNode: onAddProxyNode,
          onSelectProxyNode: onSelectProxyNode,
          onDeleteProxyNode: onDeleteProxyNode,
        ),
        const SizedBox(height: 16),
        SettingsCard(
          children: [
            ProxyConfigurationForm(
              selectedProtocol: selectedProtocol,
              proxyEnabled: enabled,
              showsUuidField: showsUuidField,
              showsTransportFields: showsTransportFields,
              showsHysteria2ObfsFields: showsHysteria2ObfsFields,
              showsPacketEncodingField: showsPacketEncodingField,
              showsTlsFields: showsTlsFields,
              proxyTlsEnabled: proxyTlsEnabled,
              selectedTransportType: selectedTransportType,
              proxyPacketEncoding: proxyPacketEncoding,
              proxyTlsInsecure: proxyTlsInsecure,
              proxyHostController: proxyHostController,
              proxyPortController: proxyPortController,
              localProxyPortController: localProxyPortController,
              proxyUuidController: proxyUuidController,
              proxyServerNameController: proxyServerNameController,
              proxyTransportPathController: proxyTransportPathController,
              proxyTransportHostController: proxyTransportHostController,
              proxyBypassDomainsController: proxyBypassDomainsController,
              onConfigurationChanged: onConfigurationChanged,
              onProtocolChanged: onProtocolChanged,
              onTlsEnabledChanged: onTlsEnabledChanged,
              onTransportTypeChanged: onTransportTypeChanged,
              onPacketEncodingChanged: onPacketEncodingChanged,
              onTlsInsecureChanged: onTlsInsecureChanged,
            ),
          ],
        ),
      ],
    );
  }
}
