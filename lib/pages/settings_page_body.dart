import 'package:flutter/material.dart';

import '../features/proxy/infrastructure/proxy_service.dart';
import '../browser/services/browser_settings_form_controller.dart';
import '../browser/widgets/settings/settings_section_widgets.dart';
import 'settings_page_home_sections.dart';

class SettingsPageScaffold extends StatelessWidget {
  const SettingsPageScaffold({
    super.key,
    required this.isLoading,
    required this.isSaving,
    required this.body,
    required this.onClose,
    required this.onSave,
  });

  final bool isLoading;
  final bool isSaving;
  final Widget body;
  final VoidCallback onClose;
  final Future<void> Function({bool closeAfterSave}) onSave;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          onClose();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('设置'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: onClose,
          ),
        ),
        body: body,
        bottomNavigationBar: isLoading
            ? null
            : SettingsHomeBottomActions(
                isSaving: isSaving,
                onCancel: onClose,
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
    required this.proxyService,
    required this.errorMessage,
    required this.buildGeneralSection,
    required this.buildVideoSection,
    required this.pushSection,
    required this.onOpenBrowserHistory,
    required this.onOpenDataManagement,
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
  });

  final bool isLoading;
  final BrowserSettingsFormController formController;
  final bool proxySupported;
  final bool isSaving;
  final bool isTestingNodeSpeed;
  final String proxyStateLabel;
  final Color Function(ColorScheme colorScheme) proxyStateColor;
  final ProxyService proxyService;
  final String? errorMessage;
  final Widget Function() buildGeneralSection;
  final Widget Function() buildVideoSection;
  final void Function({
    required String title,
    required IconData icon,
    required List<Widget> Function(BuildContext context) buildChildren,
  })
  pushSection;
  final Future<void> Function() onOpenBrowserHistory;
  final Future<void> Function() onOpenDataManagement;
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

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        SettingsPageHomeSections(
          buildGeneralSection: buildGeneralSection,
          buildVideoSection: buildVideoSection,
          pushSection: pushSection,
          onOpenBrowserHistory: onOpenBrowserHistory,
          onOpenDataManagement: onOpenDataManagement,
          formController: formController,
          proxySupported: proxySupported,
          isSaving: isSaving,
          isTestingNodeSpeed: isTestingNodeSpeed,
          proxyStateLabel: proxyStateLabel,
          proxyStateColor: proxyStateColor,
          proxyService: proxyService,
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
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
