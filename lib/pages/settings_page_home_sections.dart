import 'package:flutter/material.dart';

import '../browser/browser_settings.dart';
import '../browser/local_http_file_server_service.dart';
import '../browser/proxy_service.dart';
import '../browser/services/browser_settings_form_controller.dart';
import '../browser/widgets/settings/local_http_settings_section.dart';
import '../browser/widgets/settings/proxy_settings_section.dart';
import '../browser/widgets/settings/settings_section_widgets.dart';

class SettingsPageHomeSections extends StatelessWidget {
  const SettingsPageHomeSections({
    super.key,
    required this.buildGeneralSection,
    required this.buildVideoSection,
    required this.pushSection,
    required this.formController,
    required this.proxySupported,
    required this.isSaving,
    required this.proxyStateLabel,
    required this.proxyStateColor,
    required this.localHttpStateLabel,
    required this.localHttpStateColor,
    required this.proxyService,
    required this.localHttpFileServerService,
    required this.errorMessage,
    required this.onHandleProxyToggle,
    required this.onParseNodeLink,
    required this.onTestNodeSpeed,
    required this.onProxyProtocolChanged,
    required this.onProxyTlsEnabledChanged,
    required this.onProxyTransportTypeChanged,
    required this.onProxyPacketEncodingChanged,
    required this.onProxyTlsInsecureChanged,
    required this.onLocalHttpToggle,
    required this.onLocalHttpBindAllInterfacesChanged,
    required this.onUseSharedDownloadsDirectory,
  });

  final Widget Function() buildGeneralSection;
  final Widget Function() buildVideoSection;
  final void Function({
    required String title,
    required IconData icon,
    required List<Widget> Function(BuildContext context) buildChildren,
  })
  pushSection;
  final BrowserSettingsFormController formController;
  final bool proxySupported;
  final bool isSaving;
  final String proxyStateLabel;
  final Color Function(ColorScheme colorScheme) proxyStateColor;
  final String localHttpStateLabel;
  final Color Function(ColorScheme colorScheme) localHttpStateColor;
  final ProxyService proxyService;
  final LocalHttpFileServerService localHttpFileServerService;
  final String? errorMessage;
  final Future<void> Function(bool enabled) onHandleProxyToggle;
  final Future<void> Function() onParseNodeLink;
  final Future<void> Function() onTestNodeSpeed;
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
    return SettingsHomeSectionsCard(
      children: [
        SettingsTile(
          icon: Icons.settings_outlined,
          title: '通用',
          subtitle: '主页、历史记录',
          onTap: () => pushSection(
            title: '通用',
            icon: Icons.settings_outlined,
            buildChildren: (_) => [buildGeneralSection()],
          ),
        ),
        const Divider(height: 1),
        SettingsTile(
          icon: Icons.videocam_outlined,
          title: '视频',
          subtitle: '原生视频播放器',
          onTap: () => pushSection(
            title: '视频',
            icon: Icons.videocam_outlined,
            buildChildren: (_) => [buildVideoSection()],
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
                errorMessage: errorMessage,
                selectedProtocol: formController.selectedProtocol,
                showsUuidField: formController.showsUuidField,
                showsTransportFields: formController.showsTransportFields,
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
                onProtocolChanged: onProxyProtocolChanged,
                onTlsEnabledChanged: onProxyTlsEnabledChanged,
                onTransportTypeChanged: onProxyTransportTypeChanged,
                onPacketEncodingChanged: onProxyPacketEncodingChanged,
                onTlsInsecureChanged: onProxyTlsInsecureChanged,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        SettingsTile(
          icon: Icons.folder_shared_outlined,
          title: '本地 HTTP 文件服务',
          subtitle: '本地目录 HTTP 托管',
          onTap: () => pushSection(
            title: '本地 HTTP 文件服务',
            icon: Icons.folder_shared_outlined,
            buildChildren: (sectionContext) => [
              LocalHttpSettingsSection(
                enabled: formController.localHttpServerEnabled,
                stateLabel: localHttpStateLabel,
                stateColor: localHttpStateColor(
                  Theme.of(sectionContext).colorScheme,
                ),
                portText:
                    '监听端口：${localHttpFileServerService.boundPort?.toString() ?? '未启动'}',
                baseUrlText: localHttpFileServerService.baseUrl == null
                    ? null
                    : '访问地址：${localHttpFileServerService.baseUrl}',
                lanUrls: localHttpFileServerService.lanUrls,
                bindAllInterfaces: formController.localHttpBindAllInterfaces,
                rootPathController: formController.localHttpRootPathController,
                portController: formController.localHttpPortController,
                uploadKeyController:
                    formController.localHttpUploadKeyController,
                onToggle: onLocalHttpToggle,
                onUseSharedDownloadsDirectory: onUseSharedDownloadsDirectory,
                onBindAllInterfacesChanged: onLocalHttpBindAllInterfacesChanged,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        SettingsTile(
          icon: Icons.vpn_lock_rounded,
          title: 'P2P VPN',
          subtitle: 'EasyTier 网络配置与设备联通',
          onTap: () => Navigator.pushNamed(context, '/easytier'),
        ),
        SettingsTile(
          icon: Icons.control_camera,
          title: '远程控制',
          subtitle: '局域网设备间远程控制',
          onTap: () => Navigator.pushNamed(context, '/remote-control'),
        ),
      ],
    );
  }
}
