part of 'remote_control_setup_sections.dart';

class RemoteControlReceiverSection extends StatelessWidget {
  final RemoteControlPortConfig? portConfig;
  final bool isReceiverAudioEnabled;
  final RemoteControlState state;
  final bool isConnecting;
  final bool isReceiverRunning;
  final bool useNoTunMode;
  final ValueChanged<bool> onUseNoTunModeChanged;
  final VoidCallback onToggleReceiverMic;
  final VoidCallback onToggleReceiver;

  const RemoteControlReceiverSection({
    super.key,
    required this.portConfig,
    required this.isReceiverAudioEnabled,
    required this.state,
    required this.isConnecting,
    required this.isReceiverRunning,
    required this.useNoTunMode,
    required this.onUseNoTunModeChanged,
    required this.onToggleReceiverMic,
    required this.onToggleReceiver,
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                        const Icon(Icons.vpn_lock_outlined, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '使用非 VPN 模式',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Switch(
                          value: useNoTunMode,
                          onChanged: isReceiverRunning
                              ? null
                              : onUseNoTunModeChanged,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      useNoTunMode
                          ? '将使用 EasyTier no-tun 运行，不建立 Android VPN；该模式会禁止若轻实时通话。'
                          : '默认使用 EasyTier VPN 组网，可启用若轻实时通话。',
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
                          useNoTunMode
                              ? '实时通话不可用'
                              : (isReceiverAudioEnabled ? '麦克风已开启' : '麦克风默认关闭'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          useNoTunMode
                              ? '非 VPN 模式会禁用本地与远端开麦'
                              : state == RemoteControlState.connected
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
                    onPressed: useNoTunMode ? null : onToggleReceiverMic,
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
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isReceiverRunning
                      ? const Color(0xFFDC2626)
                      : null,
                  foregroundColor: isReceiverRunning ? Colors.white : null,
                ),
                onPressed: isConnecting ? null : onToggleReceiver,
                icon: isConnecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        isReceiverRunning
                            ? Icons.stop_circle_outlined
                            : Icons.play_arrow,
                      ),
                label: Text(
                  isConnecting
                      ? (isReceiverRunning ? '关闭中...' : '启动中...')
                      : (isReceiverRunning ? '关闭被控端' : '启动被控端'),
                ),
              ),
            ),
            if (state == RemoteControlState.connected) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('已连接', style: TextStyle(color: Colors.green)),
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
