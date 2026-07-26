part of 'remote_control_session_widgets.dart';

class FloatingTailControls extends StatelessWidget {
  const FloatingTailControls({
    super.key,
    required this.remoteHost,
    required this.isAudioEnabled,
    required this.isVoiceEnabled,
    required this.isRemoteMicEnabled,
    required this.isReceiverMode,
    required this.useTrajectorySwipe,
    required this.useAnnotationMode,
    required this.isPopupVisible,
    required this.onTailTap,
    required this.onTailDragUpdate,
    required this.onAudioTap,
    required this.onRemoteMicTap,
    required this.onOverlayTextTap,
    required this.onKeyboardTap,
    required this.onRefreshTap,
    required this.onTrajectoryToggleTap,
    required this.onAnnotationToggleTap,
    required this.onWakeScreenTap,
    required this.onMinimizeTap,
    required this.onBackTap,
    required this.onHomeTap,
    required this.onRecentsTap,
    required this.onTemporaryCloseTap,
    required this.onCloseTap,
  });

  final String remoteHost;
  final bool isAudioEnabled;
  final bool isVoiceEnabled;
  final bool isRemoteMicEnabled;
  final bool isReceiverMode;
  final bool useTrajectorySwipe;
  final bool useAnnotationMode;
  final bool isPopupVisible;
  final VoidCallback onTailTap;
  final ValueChanged<DragUpdateDetails> onTailDragUpdate;
  final VoidCallback onAudioTap;
  final VoidCallback onRemoteMicTap;
  final VoidCallback onOverlayTextTap;
  final VoidCallback onKeyboardTap;
  final VoidCallback onRefreshTap;
  final VoidCallback onTrajectoryToggleTap;
  final VoidCallback onAnnotationToggleTap;
  final VoidCallback onWakeScreenTap;
  final VoidCallback onMinimizeTap;
  final VoidCallback onBackTap;
  final VoidCallback onHomeTap;
  final VoidCallback onRecentsTap;
  final VoidCallback onTemporaryCloseTap;
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
                          if (isVoiceEnabled)
                            TailActionChip(
                              icon: audioIcon,
                              label: audioLabel,
                              accentColor: audioAccentColor,
                              onTap: onAudioTap,
                            ),
                          if (isVoiceEnabled && !isReceiverMode)
                            TailActionChip(
                              icon: isRemoteMicEnabled
                                  ? Icons.record_voice_over
                                  : Icons.voice_over_off,
                              label: isRemoteMicEnabled ? '关远端麦' : '开远端麦',
                              accentColor: isRemoteMicEnabled
                                  ? const Color(0xFF059669)
                                  : const Color(0xFF4B5563),
                              onTap: onRemoteMicTap,
                            ),
                          if (!isReceiverMode)
                            TailActionChip(
                              icon: Icons.text_fields_rounded,
                              label: '文字提示',
                              accentColor: const Color(0xFF7C3AED),
                              onTap: onOverlayTextTap,
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
                          if (!isReceiverMode)
                            TailActionChip(
                              icon: useTrajectorySwipe
                                  ? Icons.swipe_rounded
                                  : Icons.timeline_rounded,
                              label: useTrajectorySwipe ? '单向滑动' : '轨迹滑动',
                              accentColor: const Color(0xFF0F766E),
                              onTap: onTrajectoryToggleTap,
                            ),
                          if (!isReceiverMode)
                            TailActionChip(
                              icon: useAnnotationMode
                                  ? Icons.edit_off_rounded
                                  : Icons.gesture_rounded,
                              label: useAnnotationMode ? '结束标注' : '标注',
                              accentColor: useAnnotationMode
                                  ? const Color(0xFFEAB308)
                                  : const Color(0xFFCA8A04),
                              onTap: onAnnotationToggleTap,
                            ),
                          if (!isReceiverMode)
                            TailActionChip(
                              icon: Icons.light_mode_rounded,
                              label: '点亮屏幕',
                              accentColor: const Color(0xFFF59E0B),
                              onTap: onWakeScreenTap,
                            ),
                          TailActionChip(
                            icon: Icons.radar_rounded,
                            label: '悬浮',
                            accentColor: const Color(0xFF0891B2),
                            onTap: onMinimizeTap,
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
                          if (!isReceiverMode)
                            TailActionChip(
                              icon: Icons.pause_circle_outline_rounded,
                              label: '临时关闭',
                              accentColor: const Color(0xFFEA580C),
                              onTap: onTemporaryCloseTap,
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

class RemoteMinimizedFloatingDot extends StatelessWidget {
  const RemoteMinimizedFloatingDot({
    super.key,
    required this.remoteHost,
    required this.onTap,
    required this.onDragUpdate,
  });

  final String remoteHost;
  final VoidCallback onTap;
  final ValueChanged<DragUpdateDetails> onDragUpdate;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '还原远程控制 $remoteHost',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        onPanUpdate: onDragUpdate,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.primary, Color(0xFF8EBF7A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.72),
              width: 1.4,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x6663B746),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: SizedBox(
            width: 58,
            height: 58,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.radar_rounded, color: Colors.white, size: 23),
                Positioned(
                  right: 12,
                  top: 12,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF34D399),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
