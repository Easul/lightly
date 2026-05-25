import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/remote_control_protocol.dart' as protocol;
import '../services/screen_capture_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/remote_control_gesture_overlay.dart';
import '../widgets/remote_control_screen_viewer.dart';

class RemoteSessionViewport extends StatelessWidget {
  const RemoteSessionViewport({
    super.key,
    required this.frameStream,
    required this.displayRect,
    required this.remoteCaptureSize,
    required this.remoteScreenSize,
    required this.initialSps,
    required this.initialPps,
    required this.latestSpsProvider,
    required this.latestPpsProvider,
    required this.onViewerReady,
    required this.onGesture,
    required this.onInteraction,
  });

  final Stream<ScreenFrame> frameStream;
  final Rect displayRect;
  final Size remoteCaptureSize;
  final Size remoteScreenSize;
  final Uint8List? initialSps;
  final Uint8List? initialPps;
  final Uint8List? Function() latestSpsProvider;
  final Uint8List? Function() latestPpsProvider;
  final Future<void> Function() onViewerReady;
  final ValueChanged<protocol.GestureCommand> onGesture;
  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: displayRect.left,
      top: displayRect.top,
      width: displayRect.width,
      height: displayRect.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: const Color(0xFF2A2F3A)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              RemoteControlScreenViewer(
                key: ValueKey<String>(
                  '${remoteCaptureSize.width}x${remoteCaptureSize.height}',
                ),
                onViewerReady: onViewerReady,
                frameStream: frameStream,
                remoteScreenSize: remoteCaptureSize,
                initialSps: initialSps,
                initialPps: initialPps,
                latestSpsProvider: latestSpsProvider,
                latestPpsProvider: latestPpsProvider,
              ),
              RemoteControlGestureOverlay(
                displayScreenSize: remoteCaptureSize,
                targetScreenSize: remoteScreenSize,
                onGesture: onGesture,
                onInteraction: onInteraction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FloatingTailControls extends StatelessWidget {
  const FloatingTailControls({
    super.key,
    required this.remoteHost,
    required this.isAudioEnabled,
    required this.isReceiverMode,
    required this.isPopupVisible,
    required this.onTailTap,
    required this.onTailDragUpdate,
    required this.onAudioTap,
    required this.onKeyboardTap,
    required this.onRefreshTap,
    required this.onBackTap,
    required this.onHomeTap,
    required this.onRecentsTap,
    required this.onCloseTap,
  });

  final String remoteHost;
  final bool isAudioEnabled;
  final bool isReceiverMode;
  final bool isPopupVisible;
  final VoidCallback onTailTap;
  final ValueChanged<DragUpdateDetails> onTailDragUpdate;
  final VoidCallback onAudioTap;
  final VoidCallback onKeyboardTap;
  final VoidCallback onRefreshTap;
  final VoidCallback onBackTap;
  final VoidCallback onHomeTap;
  final VoidCallback onRecentsTap;
  final VoidCallback onCloseTap;

  @override
  Widget build(BuildContext context) {
    final audioLabel = isReceiverMode
        ? (isAudioEnabled ? '闭麦' : '开麦')
        : (isAudioEnabled ? '语音' : '静音');
    final audioIcon = isAudioEnabled ? Icons.mic : Icons.mic_off;
    final audioAccentColor = isAudioEnabled
        ? const Color(0xFF059669)
        : const Color(0xFF4B5563);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: !isPopupVisible
              ? const SizedBox.shrink()
              : Container(
                  width: 248,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xE6111827),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF374151)),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.circle,
                            color: Colors.greenAccent,
                            size: 12,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              remoteHost,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TailActionChip(
                            icon: audioIcon,
                            label: audioLabel,
                            accentColor: audioAccentColor,
                            onTap: onAudioTap,
                          ),
                          TailActionChip(
                            icon: Icons.keyboard_alt_outlined,
                            label: '键盘',
                            accentColor: const Color(0xFF2563EB),
                            onTap: onKeyboardTap,
                          ),
                          TailActionChip(
                            icon: Icons.refresh,
                            label: '刷新',
                            accentColor: const Color(0xFF2563EB),
                            onTap: onRefreshTap,
                          ),
                          TailActionChip(
                            icon: Icons.arrow_back,
                            label: '返回',
                            accentColor: const Color(0xFF4B5563),
                            onTap: onBackTap,
                          ),
                          TailActionChip(
                            icon: Icons.home_rounded,
                            label: 'Home',
                            accentColor: const Color(0xFF4B5563),
                            onTap: onHomeTap,
                          ),
                          TailActionChip(
                            icon: Icons.apps_rounded,
                            label: '最近',
                            accentColor: const Color(0xFF4B5563),
                            onTap: onRecentsTap,
                          ),
                          TailActionChip(
                            icon: Icons.close,
                            label: '关闭',
                            accentColor: const Color(0xFFDC2626),
                            onTap: onCloseTap,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
        if (isPopupVisible) const SizedBox(height: 8),
        GestureDetector(
          onTap: onTailTap,
          onPanUpdate: onTailDragUpdate,
          child: Container(
            width: 56,
            height: 30,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, Color(0xFF8EBF7A)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white70, width: 1.2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x6663B746),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(
              isPopupVisible
                  ? Icons.expand_less_rounded
                  : Icons.drag_handle_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }
}

class TailActionChip extends StatelessWidget {
  const TailActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class HiddenTailHandle extends StatelessWidget {
  const HiddenTailHandle({
    super.key,
    required this.onTap,
    required this.onDragUpdate,
  });

  final VoidCallback onTap;
  final ValueChanged<DragUpdateDetails> onDragUpdate;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onPanUpdate: onDragUpdate,
      child: Container(
        width: 56,
        height: 12,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x6663B746),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
      ),
    );
  }
}

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
