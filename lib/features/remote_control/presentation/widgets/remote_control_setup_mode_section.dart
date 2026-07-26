part of 'remote_control_setup_sections.dart';

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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
