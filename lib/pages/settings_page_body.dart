import 'package:flutter/material.dart';

import '../browser/local_http_file_server_service.dart';
import '../browser/proxy_service.dart';
import '../browser/services/browser_settings_form_controller.dart';
import '../browser/widgets/settings/settings_section_widgets.dart';
import 'settings_page_home_sections.dart';

class SettingsPageScaffold extends StatelessWidget {
  const SettingsPageScaffold({
    super.key,
    required this.hasAppliedChanges,
    required this.isLoading,
    required this.isSaving,
    required this.body,
    required this.onSave,
  });

  final bool hasAppliedChanges;
  final bool isLoading;
  final bool isSaving;
  final Widget body;
  final Future<void> Function({bool closeAfterSave}) onSave;

  void _popWithResult(BuildContext context) {
    Navigator.of(context).pop(hasAppliedChanges);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _popWithResult(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('设置'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _popWithResult(context),
          ),
        ),
        body: body,
        bottomNavigationBar: isLoading
            ? null
            : SettingsHomeBottomActions(
                isSaving: isSaving,
                onCancel: () => _popWithResult(context),
                onSave: onSave,
              ),
      ),
    );
  }
}

class SettingsPageBody extends StatelessWidget {
  const SettingsPageBody({
    super.key,
    required this.isLoading,
    required this.formController,
    required this.proxySupported,
    required this.isSaving,
    required this.isTestingNodeSpeed,
    required this.proxyStateLabel,
    required this.proxyStateColor,
    required this.localHttpStateLabel,
    required this.localHttpStateColor,
    required this.proxyService,
    required this.localHttpFileServerService,
    required this.errorMessage,
    required this.buildGeneralSection,
    required this.buildVideoSection,
    required this.pushSection,
    required this.onHandleProxyToggle,
    required this.onParseNodeLink,
    required this.onTestNodeSpeed,
    required this.onCancelTestSpeed,
    required this.onAddProxyNode,
    required this.onSelectProxyNode,
    required this.onDeleteProxyNode,
    required this.onProxyConfigurationChanged,
    required this.onProxyProtocolChanged,
    required this.onProxyTlsEnabledChanged,
    required this.onProxyTransportTypeChanged,
    required this.onProxyPacketEncodingChanged,
    required this.onProxyTlsInsecureChanged,
    required this.onLocalHttpToggle,
    required this.onLocalHttpBindAllInterfacesChanged,
    required this.onUseSharedDownloadsDirectory,
  });

  final bool isLoading;
  final BrowserSettingsFormController formController;
  final bool proxySupported;
  final bool isSaving;
  final bool isTestingNodeSpeed;
  final String proxyStateLabel;
  final Color Function(ColorScheme colorScheme) proxyStateColor;
  final String localHttpStateLabel;
  final Color Function(ColorScheme colorScheme) localHttpStateColor;
  final ProxyService proxyService;
  final LocalHttpFileServerService localHttpFileServerService;
  final String? errorMessage;
  final Widget Function() buildGeneralSection;
  final Widget Function() buildVideoSection;
  final void Function({
    required String title,
    required IconData icon,
    required List<Widget> Function(BuildContext context) buildChildren,
  })
  pushSection;
  final Future<void> Function(bool enabled) onHandleProxyToggle;
  final Future<void> Function() onParseNodeLink;
  final Future<void> Function() onTestNodeSpeed;
  final VoidCallback onCancelTestSpeed;
  final VoidCallback onAddProxyNode;
  final ValueChanged<String> onSelectProxyNode;
  final ValueChanged<String> onDeleteProxyNode;
  final VoidCallback onProxyConfigurationChanged;
  final ValueChanged<String> onProxyProtocolChanged;
  final ValueChanged<bool> onProxyTlsEnabledChanged;
  final ValueChanged<String> onProxyTransportTypeChanged;
  final ValueChanged<String> onProxyPacketEncodingChanged;
  final ValueChanged<bool> onProxyTlsInsecureChanged;
  final ValueChanged<bool> onLocalHttpToggle;
  final ValueChanged<bool> onLocalHttpBindAllInterfacesChanged;
  final Future<void> Function() onUseSharedDownloadsDirectory;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SettingsPageHomeSections(
          buildGeneralSection: buildGeneralSection,
          buildVideoSection: buildVideoSection,
          pushSection: pushSection,
          formController: formController,
          proxySupported: proxySupported,
          isSaving: isSaving,
          isTestingNodeSpeed: isTestingNodeSpeed,
          proxyStateLabel: proxyStateLabel,
          proxyStateColor: proxyStateColor,
          localHttpStateLabel: localHttpStateLabel,
          localHttpStateColor: localHttpStateColor,
          proxyService: proxyService,
          localHttpFileServerService: localHttpFileServerService,
          errorMessage: errorMessage,
          onHandleProxyToggle: onHandleProxyToggle,
          onParseNodeLink: onParseNodeLink,
          onTestNodeSpeed: onTestNodeSpeed,
          onCancelTestSpeed: onCancelTestSpeed,
          onAddProxyNode: onAddProxyNode,
          onSelectProxyNode: onSelectProxyNode,
          onDeleteProxyNode: onDeleteProxyNode,
          onProxyConfigurationChanged: onProxyConfigurationChanged,
          onProxyProtocolChanged: onProxyProtocolChanged,
          onProxyTlsEnabledChanged: onProxyTlsEnabledChanged,
          onProxyTransportTypeChanged: onProxyTransportTypeChanged,
          onProxyPacketEncodingChanged: onProxyPacketEncodingChanged,
          onProxyTlsInsecureChanged: onProxyTlsInsecureChanged,
          onLocalHttpToggle: onLocalHttpToggle,
          onLocalHttpBindAllInterfacesChanged:
              onLocalHttpBindAllInterfacesChanged,
          onUseSharedDownloadsDirectory: onUseSharedDownloadsDirectory,
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
