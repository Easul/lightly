import 'package:flutter/material.dart';

import '../browser/browser_settings.dart';
import '../browser/proxy_service.dart';
import '../browser/services/browser_settings_form_controller.dart';
import '../browser/widgets/settings/proxy_settings_section.dart';
import '../browser/widgets/settings/settings_section_widgets.dart';

class SettingsPageHomeSections extends StatelessWidget {
  const SettingsPageHomeSections({
    super.key,
    required this.buildGeneralSection,
    required this.buildVideoSection,
    required this.pushSection,
    required this.onOpenBrowserHistory,
    required this.onOpenDataManagement,
    required this.formController,
    required this.proxySupported,
    required this.isSaving,
    required this.isTestingNodeSpeed,
    required this.proxyStateLabel,
    required this.proxyStateColor,
    required this.proxyService,
    required this.errorMessage,
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
  final BrowserSettingsFormController formController;
  final bool proxySupported;
  final bool isSaving;
  final bool isTestingNodeSpeed;
  final String proxyStateLabel;
  final Color Function(ColorScheme colorScheme) proxyStateColor;
  final ProxyService proxyService;
  final String? errorMessage;
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
    return Column(
      children: [
        SettingsHomeSectionsCard(
          children: [
            SettingsTile(
              icon: Icons.settings_outlined,
              title: '通用',
              subtitle: '主页、浏览器选项',
              onTap: () => _pushSingleSection(
                title: '通用',
                icon: Icons.settings_outlined,
                buildSection: buildGeneralSection,
              ),
            ),
            const Divider(height: 1),
            SettingsTile(
              icon: Icons.history_rounded,
              title: '历史浏览',
              subtitle: '查看、搜索和清理浏览历史',
              onTap: () => onOpenBrowserHistory(),
            ),
            const Divider(height: 1),
            SettingsTile(
              icon: Icons.import_export_rounded,
              title: '数据管理',
              subtitle: '导入导出、运行日志与备份恢复',
              onTap: () => onOpenDataManagement(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SettingsHomeSectionsCard(
          children: [
            SettingsTile(
              icon: Icons.videocam_outlined,
              title: '视频',
              subtitle: '原生视频播放器',
              onTap: () => _pushSingleSection(
                title: '视频',
                icon: Icons.videocam_outlined,
                buildSection: buildVideoSection,
              ),
            ),
            const Divider(height: 1),
            SettingsTile(
              icon: Icons.shield_outlined,
              title: '代理',
              subtitle: '代理协议、服务器、端口',
              onTap: () => pushSection(
                title: '代理',
                icon: Icons.shield_outlined,
                buildChildren: (sectionContext) => [
                  ProxySettingsSection(
                    enabled: formController.proxyEnabled,
                    supported: proxySupported,
                    isSaving: isSaving,
                    isTestingNodeSpeed: isTestingNodeSpeed,
                    stateLabel: proxyStateLabel,
                    stateColor: proxyStateColor(
                      Theme.of(sectionContext).colorScheme,
                    ),
                    detailText:
                        formController.selectedProtocol ==
                                BrowserProxyProtocol.vless ||
                            formController.selectedProtocol ==
                                BrowserProxyProtocol.hysteria2
                        ? '本地 mixed 端口（HTTP + SOCKS5）：${proxyService.localProxyPort?.toString() ?? '未启动'}'
                        : '代理地址：${formController.proxyHostController.text.trim().isEmpty ? '未设置' : '${formController.proxyHostController.text.trim()}:${formController.proxyPortController.text.trim()}'}',
                    nodeLinkController: formController.nodeLinkController,
                    proxyNodes: formController.proxyNodes,
                    selectedProxyNodeId: formController.selectedProxyNodeId,
                    errorMessage: errorMessage,
                    selectedProtocol: formController.selectedProtocol,
                    showsUuidField: formController.showsUuidField,
                    showsTransportFields: formController.showsTransportFields,
                    showsHysteria2ObfsFields:
                        formController.showsHysteria2ObfsFields,
                    showsPacketEncodingField:
                        formController.showsPacketEncodingField,
                    showsTlsFields: formController.showsTlsFields,
                    proxyTlsEnabled: formController.proxyTlsEnabled,
                    selectedTransportType: formController.selectedTransportType,
                    proxyPacketEncoding: formController.proxyPacketEncoding,
                    proxyTlsInsecure: formController.proxyTlsInsecure,
                    proxyHostController: formController.proxyHostController,
                    proxyPortController: formController.proxyPortController,
                    localProxyPortController:
                        formController.localProxyPortController,
                    proxyUuidController: formController.proxyUuidController,
                    proxyServerNameController:
                        formController.proxyServerNameController,
                    proxyTransportPathController:
                        formController.proxyTransportPathController,
                    proxyTransportHostController:
                        formController.proxyTransportHostController,
                    proxyBypassDomainsController:
                        formController.proxyBypassDomainsController,
                    onToggle: onHandleProxyToggle,
                    onParse: onParseNodeLink,
                    onTestSpeed: onTestNodeSpeed,
                    onCancelTestSpeed: onCancelTestSpeed,
                    onAddProxyNode: onAddProxyNode,
                    onSelectProxyNode: onSelectProxyNode,
                    onDeleteProxyNode: onDeleteProxyNode,
                    onConfigurationChanged: onProxyConfigurationChanged,
                    onProtocolChanged: onProxyProtocolChanged,
                    onTlsEnabledChanged: onProxyTlsEnabledChanged,
                    onTransportTypeChanged: onProxyTransportTypeChanged,
                    onPacketEncodingChanged: onProxyPacketEncodingChanged,
                    onTlsInsecureChanged: onProxyTlsInsecureChanged,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SettingsHomeSectionsCard(
          children: [
            SettingsTile(
              icon: Icons.info_outline_rounded,
              title: '版本',
              subtitle: '关于若轻与版本信息',
              onTap: () => Navigator.of(context).pushNamed('/about-version'),
            ),
          ],
        ),
      ],
    );
  }

  void _pushSingleSection({
    required String title,
    required IconData icon,
    required Widget Function() buildSection,
  }) {
    pushSection(
      title: title,
      icon: icon,
      buildChildren: (_) => [buildSection()],
    );
  }
}
