part of 'remote_control_setup_sections.dart';

class RemoteControlControllerSection extends StatelessWidget {
  final List<Map<String, String>> peers;
  final bool isEasyTierRunning;
  final bool isEasyTierNoTunMode;
  final bool isLoadingPeers;
  final TextEditingController hostController;
  final TextEditingController controlPortController;
  final TextEditingController screenPortController;
  final RemoteControlPortConfig? portConfig;
  final bool isConnecting;
  final bool useInternalProxy;
  final bool isProxyRunning;
  final VoidCallback onReloadPeers;
  final void Function(Map<String, String> peer) onSelectPeer;
  final ValueChanged<int> onControlPortChanged;
  final ValueChanged<int> onScreenPortChanged;
  final ValueChanged<bool> onUseInternalProxyChanged;
  final VoidCallback onConnect;

  const RemoteControlControllerSection({
    super.key,
    required this.peers,
    required this.isEasyTierRunning,
    required this.isEasyTierNoTunMode,
    required this.isLoadingPeers,
    required this.hostController,
    required this.controlPortController,
    required this.screenPortController,
    required this.portConfig,
    required this.isConnecting,
    required this.useInternalProxy,
    required this.isProxyRunning,
    required this.onReloadPeers,
    required this.onSelectPeer,
    required this.onControlPortChanged,
    required this.onScreenPortChanged,
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (peers.isNotEmpty) ...[
              const Text(
                '已发现的设备',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              ...peers.map(
                (peer) => RemoteControlPeerTile(
                  name: peer['name'] ?? '未命名设备',
                  ip: peer['ip'] ?? '',
                  mode: peer['mode'] ?? '',
                  latency: peer['latency'] ?? '',
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
            if (isEasyTierNoTunMode) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '当前 P2P VPN 使用非 VPN 模式，主控端会继续通过非 VPN 模式连接被控端。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
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
            const SizedBox(height: 16),
            const Text(
              '提示：点击连接会先自动检测可用端口；使用内置代理连接时仅支持屏幕控制，语音会自动关闭。',
              style: TextStyle(color: Colors.grey, fontSize: 12),
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
