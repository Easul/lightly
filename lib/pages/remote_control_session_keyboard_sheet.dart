part of 'remote_control_session_widgets.dart';

class RemoteKeyboardSheet extends StatelessWidget {
  const RemoteKeyboardSheet({
    super.key,
    required this.controller,
    required this.onSendText,
    required this.onSpace,
    required this.onEnter,
    required this.onDelete,
    required this.onTab,
  });

  final TextEditingController controller;
  final Future<void> Function(String text) onSendText;
  final VoidCallback onSpace;
  final VoidCallback onEnter;
  final VoidCallback onDelete;
  final VoidCallback onTab;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '远程键盘输入',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: '在这里输入后发送到被控端',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF1F2937),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF374151)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF374151)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF60A5FA)),
              ),
            ),
            onSubmitted: (value) async {
              if (value.isEmpty) return;
              await onSendText(value);
              controller.clear();
            },
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, child) {
              return FilledButton.icon(
                onPressed: value.text.isEmpty
                    ? null
                    : () async {
                        await onSendText(value.text);
                        controller.clear();
                      },
                icon: const Icon(Icons.send_rounded),
                label: const Text('发送文本'),
              );
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              RemoteKeyboardQuickActionChip(
                icon: Icons.space_bar_rounded,
                label: '空格',
                onTap: onSpace,
              ),
              RemoteKeyboardQuickActionChip(
                icon: Icons.keyboard_return_rounded,
                label: '回车',
                onTap: onEnter,
              ),
              RemoteKeyboardQuickActionChip(
                icon: Icons.backspace_outlined,
                label: '退格',
                onTap: onDelete,
              ),
              RemoteKeyboardQuickActionChip(
                icon: Icons.keyboard_tab_rounded,
                label: 'Tab',
                onTap: onTab,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RemoteKeyboardQuickActionChip extends StatelessWidget {
  const RemoteKeyboardQuickActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, color: Colors.white, size: 18),
      backgroundColor: const Color(0xFF1F2937),
      label: Text(label, style: const TextStyle(color: Colors.white)),
      side: const BorderSide(color: Color(0xFF374151)),
      onPressed: onTap,
    );
  }
}
