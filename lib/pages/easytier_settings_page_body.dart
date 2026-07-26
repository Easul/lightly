import 'package:flutter/material.dart';

import '../features/easytier/domain/easytier_config.dart';
import '../features/easytier/domain/easytier_network_profile.dart';
import '../features/easytier/presentation/easytier_sections.dart';

class EasyTierSettingsBody extends StatelessWidget {
  const EasyTierSettingsBody({
    super.key,
    required this.formKey,
    required this.isRunning,
    required this.isLoading,
    required this.statusMessage,
    required this.errorMessage,
    required this.profiles,
    required this.selectedProfileId,
    required this.peerSummaries,
    required this.diagnostics,
    required this.displayNetworkInfo,
    required this.easyTierIp,
    required this.localHttpReachable,
    required this.localHttpSubtitle,
    required this.clipboardReachable,
    required this.clipboardSubtitle,
    required this.instanceNameController,
    required this.networkNameController,
    required this.networkSecretController,
    required this.dhcp,
    required this.ipv4Controller,
    required this.hostnameController,
    required this.enableP2p,
    required this.noTun,
    required this.portMappingPortController,
    required this.portMappings,
    required this.portMappingsExpanded,
    required this.peerController,
    required this.peers,
    required this.peerRemarks,
    required this.activePeerIndex,
    required this.onSelectProfile,
    required this.onCreateProfile,
    required this.onDeleteProfile,
    required this.onCopyNetworkInfo,
    required this.onEnableLocalHttp,
    required this.onStartClipboard,
    required this.onStartVpn,
    required this.onStopVpn,
    required this.onDhcpChanged,
    required this.onEnableP2pChanged,
    required this.onNoTunChanged,
    required this.onPortMappingsExpandedChanged,
    required this.onAddPortMapping,
    required this.onRemovePortMapping,
    required this.onPortMappingRemarkChanged,
    required this.onAddPeer,
    required this.onRemovePeer,
    required this.onSelectPeer,
    required this.onPeerRemarkChanged,
  });

  final GlobalKey<FormState> formKey;
  final bool isRunning;
  final bool isLoading;
  final String? statusMessage;
  final String? errorMessage;
  final List<EasyTierNetworkProfile> profiles;
  final String? selectedProfileId;
  final List<Map<String, String>> peerSummaries;
  final List<String> diagnostics;
  final String displayNetworkInfo;
  final String? easyTierIp;
  final bool localHttpReachable;
  final String localHttpSubtitle;
  final bool clipboardReachable;
  final String clipboardSubtitle;
  final TextEditingController instanceNameController;
  final TextEditingController networkNameController;
  final TextEditingController networkSecretController;
  final bool dhcp;
  final TextEditingController ipv4Controller;
  final TextEditingController hostnameController;
  final bool enableP2p;
  final bool noTun;
  final TextEditingController portMappingPortController;
  final List<EasyTierPortMapping> portMappings;
  final bool portMappingsExpanded;
  final TextEditingController peerController;
  final List<String> peers;
  final List<String> peerRemarks;
  final int? activePeerIndex;
  final ValueChanged<String?> onSelectProfile;
  final VoidCallback onCreateProfile;
  final VoidCallback onDeleteProfile;
  final VoidCallback onCopyNetworkInfo;
  final VoidCallback onEnableLocalHttp;
  final VoidCallback onStartClipboard;
  final VoidCallback onStartVpn;
  final VoidCallback onStopVpn;
  final ValueChanged<bool> onDhcpChanged;
  final ValueChanged<bool> onEnableP2pChanged;
  final ValueChanged<bool> onNoTunChanged;
  final ValueChanged<bool> onPortMappingsExpandedChanged;
  final VoidCallback onAddPortMapping;
  final ValueChanged<int> onRemovePortMapping;
  final void Function(int index, String remark) onPortMappingRemarkChanged;
  final VoidCallback onAddPeer;
  final ValueChanged<int> onRemovePeer;
  final ValueChanged<int> onSelectPeer;
  final void Function(int index, String remark) onPeerRemarkChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EasyTierStatusCard(
                isRunning: isRunning,
                isNoTunMode: noTun,
                statusMessage: statusMessage,
                errorMessage: errorMessage,
              ),
              const SizedBox(height: 16),
              if (profiles.isNotEmpty) ...[
                EasyTierProfilesCard(
                  selectedProfileId: selectedProfileId,
                  profileItems: profiles
                      .map(
                        (profile) => DropdownMenuItem<String>(
                          value: profile.id,
                          child: Text(profile.name),
                        ),
                      )
                      .toList(),
                  isLoading: isLoading,
                  canDelete: profiles.length > 1,
                  onSelected: onSelectProfile,
                  onCreate: onCreateProfile,
                  onDelete: onDeleteProfile,
                ),
                const SizedBox(height: 16),
              ],
              if (displayNetworkInfo.isNotEmpty) ...[
                EasyTierNetworkInfoCard(
                  peerSummaries: peerSummaries,
                  diagnostics: diagnostics,
                  displayNetworkInfo: displayNetworkInfo,
                  onCopy: onCopyNetworkInfo,
                ),
                const SizedBox(height: 16),
              ],
              if (easyTierIp != null) ...[
                EasyTierInternalServicesCard(
                  easyTierIp: easyTierIp!,
                  localHttpReachable: localHttpReachable,
                  localHttpSubtitle: localHttpSubtitle,
                  clipboardReachable: clipboardReachable,
                  clipboardSubtitle: clipboardSubtitle,
                  onEnableLocalHttp: onEnableLocalHttp,
                  onStartClipboard: onStartClipboard,
                ),
                const SizedBox(height: 16),
              ],
              EasyTierControlButtons(
                isLoading: isLoading,
                isRunning: isRunning,
                isNoTunMode: noTun,
                onStart: onStartVpn,
                onStop: onStopVpn,
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              EasyTierConfigurationSection(
                instanceNameController: instanceNameController,
                networkNameController: networkNameController,
                networkSecretController: networkSecretController,
                dhcp: dhcp,
                ipv4Controller: ipv4Controller,
                hostnameController: hostnameController,
                enableP2p: enableP2p,
                noTun: noTun,
                portMappingPortController: portMappingPortController,
                portMappings: portMappings,
                portMappingsExpanded: portMappingsExpanded,
                peerController: peerController,
                peers: peers,
                peerRemarks: peerRemarks,
                activePeerIndex: activePeerIndex,
                onDhcpChanged: onDhcpChanged,
                onEnableP2pChanged: onEnableP2pChanged,
                onNoTunChanged: onNoTunChanged,
                onPortMappingsExpandedChanged: onPortMappingsExpandedChanged,
                onAddPortMapping: onAddPortMapping,
                onRemovePortMapping: onRemovePortMapping,
                onPortMappingRemarkChanged: onPortMappingRemarkChanged,
                onAddPeer: onAddPeer,
                onRemovePeer: onRemovePeer,
                onSelectPeer: onSelectPeer,
                onPeerRemarkChanged: onPeerRemarkChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
