import 'package:flutter/material.dart';

import '../models/remote_control_config.dart';
import '../services/remote_control_service.dart';

class RemoteControlModeSelectorSection extends StatelessWidget {
  final RemoteControlMode selectedMode;
  final VoidCallback onReceiverTap;
  final VoidCallback onControllerTap;

  const RemoteControlModeSelectorSection({
    super.key,
    required this.selectedMode,
    required this.onReceiverTap,
    required this.onControllerTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择模式',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: RemoteControlModeCard(
                    icon: Icons.phone_android,
                    title: '被控端',
                    subtitle: '允许其他设备控制此设备',
                    isSelected: selectedMode == RemoteControlMode.receiver,
                    onTap: onReceiverTap,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: RemoteControlModeCard(
                    icon: Icons.control_camera,
                    title: '主控端',
                    subtitle: '控制其他设备',
                    isSelected: selectedMode == RemoteControlMode.controller,
                    onTap: onControllerTap,
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

class RemoteControlReceiverSection extends StatelessWidget {
  final RemoteControlPortConfig? portConfig;
  final bool isReceiverAudioEnabled;
  final RemoteControlState state;
  final bool isConnecting;
  final VoidCallback onToggleReceiverMic;
  final VoidCallback onStartReceiver;

  const RemoteControlReceiverSection({
    super.key,
    required this.portConfig,
    required this.isReceiverAudioEnabled,
    required this.state,
    required this.isConnecting,
    required this.onToggleReceiverMic,
    required this.onStartReceiver,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '被控端设置',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (portConfig != null) ...[
              RemoteControlInfoRow(
                label: '控制端口',
                value: '${portConfig!.controlPort}',
              ),
              RemoteControlInfoRow(
                label: '屏幕端口',
                value: '${portConfig!.screenPort}',
              ),
              RemoteControlInfoRow(
                label: '语音端口',
                value: '${portConfig!.audioPort}',
              ),
              const SizedBox(height: 16),
            ],
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF374151)),
              ),
              child: Row(
                children: [
                  Icon(
                    isReceiverAudioEnabled ? Icons.mic : Icons.mic_off,
                    color: isReceiverAudioEnabled ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isReceiverAudioEnabled ? '麦克风已开启' : '麦克风默认关闭',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          state == RemoteControlState.connected
                              ? (isReceiverAudioEnabled
                                    ? '主控端当前可以听到被控端声音'
                                    : '主控端当前听不到被控端声音')
                              : '等待主控端连接后，可手动开麦',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: onToggleReceiverMic,
                    icon: Icon(
                      isReceiverAudioEnabled ? Icons.mic_off : Icons.mic,
                    ),
                    label: Text(isReceiverAudioEnabled ? '闭麦' : '开麦'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '提示：请确保主控端和被控端在同一局域网内（通过 EasyTier 连接）',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isConnecting ? null : onStartReceiver,
                icon: isConnecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(isConnecting ? '启动中...' : '启动被控端'),
              ),
            ),
            if (state == RemoteControlState.connected) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('已连接', style: const TextStyle(color: Colors.green)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RemoteControlControllerSection extends StatelessWidget {
  final List<Map<String, String>> peers;
  final bool isEasyTierRunning;
  final bool isLoadingPeers;
  final TextEditingController hostController;
  final TextEditingController controlPortController;
  final TextEditingController screenPortController;
  final TextEditingController audioPortController;
  final RemoteControlPortConfig? portConfig;
  final bool isConnecting;
  final bool useInternalProxy;
  final bool isProxyRunning;
  final VoidCallback onReloadPeers;
  final void Function(Map<String, String> peer) onSelectPeer;
  final ValueChanged<int> onControlPortChanged;
  final ValueChanged<int> onScreenPortChanged;
  final ValueChanged<int> onAudioPortChanged;
  final ValueChanged<bool> onUseInternalProxyChanged;
  final VoidCallback onConnect;

  const RemoteControlControllerSection({
    super.key,
    required this.peers,
    required this.isEasyTierRunning,
    required this.isLoadingPeers,
    required this.hostController,
    required this.controlPortController,
    required this.screenPortController,
    required this.audioPortController,
    required this.portConfig,
    required this.isConnecting,
    required this.useInternalProxy,
    required this.isProxyRunning,
    required this.onReloadPeers,
    required this.onSelectPeer,
    required this.onControlPortChanged,
    required this.onScreenPortChanged,
    required this.onAudioPortChanged,
    required this.onUseInternalProxyChanged,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '主控端设置',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (peers.isNotEmpty) ...[
              const Text(
                '已发现的设备',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              ...peers.map(
                (peer) => RemoteControlPeerTile(
                  name: peer['name'] ?? '未命名设备',
                  ip: peer['ip'] ?? '',
                  onTap: () => onSelectPeer(peer),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
            ],
            if (isEasyTierRunning && peers.isEmpty && !isLoadingPeers)
              TextButton.icon(
                onPressed: onReloadPeers,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新设备列表'),
              ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.router,
                          size: 20,
                          color: isProxyRunning ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '使用内置代理连接',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Switch(
                          value: useInternalProxy,
                          onChanged: isProxyRunning
                              ? onUseInternalProxyChanged
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isProxyRunning
                          ? '数据将通过浏览器代理转发到服务器，由服务器与被控端P2P通信'
                          : '请先在设置中配置并启用代理',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: hostController,
              decoration: InputDecoration(
                labelText: '被控端地址',
                hintText: useInternalProxy
                    ? '例如: 10.126.126.2 (通过代理转发)'
                    : '例如: 10.126.126.2 或 192.168.1.100',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            RemoteControlPortInput(
              label: '控制端口',
              controller: controlPortController,
              onChanged: onControlPortChanged,
            ),
            const SizedBox(height: 8),
            RemoteControlPortInput(
              label: '屏幕端口',
              controller: screenPortController,
              onChanged: onScreenPortChanged,
            ),
            const SizedBox(height: 8),
            RemoteControlPortInput(
              label: '语音端口',
              controller: audioPortController,
              onChanged: onAudioPortChanged,
            ),
            const SizedBox(height: 16),
            const Text(
              '提示：请确保被控端已启动，并输入正确的地址和端口',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isConnecting ? null : onConnect,
                icon: isConnecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(isConnecting ? '连接中...' : '连接'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RemoteControlModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const RemoteControlModeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).primaryColor.withOpacity(0.1)
              : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 48,
              color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isSelected
                    ? Theme.of(context).primaryColor.withOpacity(0.7)
                    : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RemoteControlInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const RemoteControlInfoRow({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class RemoteControlPortInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<int> onChanged;

  const RemoteControlPortInput({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final port = int.tryParse(value);
              if (port != null && port > 0 && port < 65536) {
                onChanged(port);
              }
            },
          ),
        ),
      ],
    );
  }
}

class RemoteControlPeerTile extends StatelessWidget {
  final String name;
  final String ip;
  final VoidCallback onTap;

  const RemoteControlPeerTile({
    super.key,
    required this.name,
    required this.ip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.phone_android),
      title: Text(name),
      subtitle: Text(ip),
      onTap: onTap,
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }
}
