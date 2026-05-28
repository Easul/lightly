import 'package:flutter/material.dart';

class EasyTierStatusCard extends StatelessWidget {
  const EasyTierStatusCard({
    super.key,
    required this.isRunning,
    required this.statusMessage,
    required this.errorMessage,
  });

  final bool isRunning;
  final String? statusMessage;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isRunning ? Icons.check_circle : Icons.cancel,
                  color: isRunning ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  isRunning ? 'VPN 运行中' : 'VPN 未运行',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            if (statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(statusMessage!),
            ],
            if (errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                '错误: $errorMessage',
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EasyTierProfilesCard extends StatelessWidget {
  const EasyTierProfilesCard({
    super.key,
    required this.selectedProfileId,
    required this.profileItems,
    required this.isLoading,
    required this.canDelete,
    required this.onSelected,
    required this.onCreate,
    required this.onDelete,
  });

  final String? selectedProfileId;
  final List<DropdownMenuItem<String>> profileItems;
  final bool isLoading;
  final bool canDelete;
  final ValueChanged<String?> onSelected;
  final VoidCallback onCreate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('网络配置档案', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedProfileId,
              items: profileItems,
              onChanged: isLoading ? null : onSelected,
              decoration: const InputDecoration(
                labelText: '当前网络',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : onCreate,
                    icon: const Icon(Icons.add),
                    label: const Text('新增网络'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading || !canDelete ? null : onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除当前'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class EasyTierNetworkInfoCard extends StatelessWidget {
  const EasyTierNetworkInfoCard({
    super.key,
    required this.peerSummaries,
    required this.diagnostics,
    required this.displayNetworkInfo,
    required this.onCopy,
  });

  final List<Map<String, String>> peerSummaries;
  final List<String> diagnostics;
  final String displayNetworkInfo;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('网络信息', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                if (peerSummaries.isNotEmpty)
                  Text(
                    '设备数: ${peerSummaries.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const Spacer(),
                IconButton(
                  tooltip: '复制网络信息',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...diagnostics.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (peerSummaries.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...peerSummaries.map(
                (peer) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.devices_rounded),
                  title: Text(peer['name'] ?? '未命名设备'),
                  subtitle: Text(
                    '${peer['ip'] ?? '未分配 IP'}\n${peer['mode'] ?? ''} · ${peer['status'] ?? ''}',
                  ),
                  isThreeLine: true,
                  trailing: Text(peer['latency'] ?? '-'),
                ),
              ),
              const Divider(),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      displayNetworkInfo,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EasyTierInternalServicesCard extends StatelessWidget {
  const EasyTierInternalServicesCard({
    super.key,
    required this.easyTierIp,
    required this.localHttpReachable,
    required this.localHttpSubtitle,
    required this.clipboardReachable,
    required this.clipboardSubtitle,
    required this.onEnableLocalHttp,
    required this.onStartClipboard,
  });

  final String easyTierIp;
  final bool localHttpReachable;
  final String localHttpSubtitle;
  final bool clipboardReachable;
  final String clipboardSubtitle;
  final VoidCallback onEnableLocalHttp;
  final VoidCallback onStartClipboard;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('VPN 内部服务访问', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SelectableText('EasyTier IP: $easyTierIp'),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_shared_rounded),
              title: const Text('本地 HTTP 文件服务 (3001)'),
              subtitle: Text(localHttpSubtitle),
              trailing: localHttpReachable
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : TextButton(
                      onPressed: onEnableLocalHttp,
                      child: const Text('启用'),
                    ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.content_paste_rounded),
              title: const Text('剪贴板服务 (12345)'),
              subtitle: Text(clipboardSubtitle),
              trailing: clipboardReachable
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : TextButton(
                      onPressed: onStartClipboard,
                      child: const Text('启动'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class EasyTierControlButtons extends StatelessWidget {
  const EasyTierControlButtons({
    super.key,
    required this.isLoading,
    required this.isRunning,
    required this.onStart,
    required this.onStop,
  });

  final bool isLoading;
  final bool isRunning;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isLoading || isRunning ? null : onStart,
            icon: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: const Text('启动 VPN'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isLoading || !isRunning ? null : onStop,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            icon: const Icon(Icons.stop),
            label: const Text('停止 VPN'),
          ),
        ),
      ],
    );
  }
}

class EasyTierConfigurationSection extends StatelessWidget {
  const EasyTierConfigurationSection({
    super.key,
    required this.instanceNameController,
    required this.networkNameController,
    required this.networkSecretController,
    required this.dhcp,
    required this.ipv4Controller,
    required this.hostnameController,
    required this.enableP2p,
    required this.peerController,
    required this.peers,
    required this.onDhcpChanged,
    required this.onEnableP2pChanged,
    required this.onAddPeer,
    required this.onRemovePeer,
  });

  final TextEditingController instanceNameController;
  final TextEditingController networkNameController;
  final TextEditingController networkSecretController;
  final bool dhcp;
  final TextEditingController ipv4Controller;
  final TextEditingController hostnameController;
  final bool enableP2p;
  final TextEditingController peerController;
  final List<String> peers;
  final ValueChanged<bool> onDhcpChanged;
  final ValueChanged<bool> onEnableP2pChanged;
  final VoidCallback onAddPeer;
  final ValueChanged<int> onRemovePeer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('网络配置', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextFormField(
          controller: instanceNameController,
          decoration: const InputDecoration(
            labelText: '实例名称',
            hintText: '例如: ruoqing_vpn',
            border: OutlineInputBorder(),
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? '请输入实例名称' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: networkNameController,
          decoration: const InputDecoration(
            labelText: '网络名称',
            hintText: '用于标识虚拟网络',
            border: OutlineInputBorder(),
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? '请输入网络名称' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: networkSecretController,
          decoration: const InputDecoration(
            labelText: '网络密码 (可选)',
            hintText: '用于网络认证',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('自动分配 IP (DHCP)'),
          subtitle: const Text(
            '若长期拿不到 virtual_ipv4，建议关闭 DHCP 并为每台设备手动填写不同的 10.144.144.x/24',
          ),
          value: dhcp,
          onChanged: onDhcpChanged,
        ),
        if (!dhcp) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: ipv4Controller,
            decoration: const InputDecoration(
              labelText: 'IP 地址',
              hintText: '例如: 10.144.144.2/24',
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
                !dhcp && (value == null || value.trim().isEmpty)
                ? '请输入 IP 地址或启用 DHCP'
                : null,
          ),
        ],
        const SizedBox(height: 16),
        TextFormField(
          controller: hostnameController,
          decoration: const InputDecoration(
            labelText: '主机名 (可选)',
            hintText: '留空时自动使用实例名称',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('启用 P2P 打洞'),
          subtitle: const Text('允许与其他节点直接连接'),
          value: enableP2p,
          onChanged: onEnableP2pChanged,
        ),
        const SizedBox(height: 16),
        Text('节点地址 (Peers)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: peerController,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '例如: tcp://peer.example.com:11010',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: onAddPeer,
            icon: const Icon(Icons.add),
            label: const Text('添加'),
          ),
        ),
        if (peers.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...peers.asMap().entries.map(
            (entry) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.link_rounded),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      entry.value,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => onRemovePeer(entry.key),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
