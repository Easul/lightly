import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/remote_control_protocol.dart' as protocol;
import '../services/screen_capture_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/remote_control_gesture_overlay.dart';
import '../widgets/remote_control_screen_viewer.dart';

Rect computeRemoteSessionFittedRect(Size viewportSize, Size remoteSize) {
  final widthScale = viewportSize.width / remoteSize.width;
  final heightScale = viewportSize.height / remoteSize.height;
  final scale = widthScale < heightScale ? widthScale : heightScale;
  final fittedWidth = remoteSize.width * scale;
  final fittedHeight = remoteSize.height * scale;
  final left = (viewportSize.width - fittedWidth) / 2;
  final top = (viewportSize.height - fittedHeight) / 2;
  return Rect.fromLTWH(left, top, fittedWidth, fittedHeight);
}

Offset resolveRemoteTailOffset({
  required Rect fittedRect,
  required BoxConstraints constraints,
  required Offset? currentOffset,
  required bool isPopupVisible,
}) {
  final tailLeft = (fittedRect.center.dx - 28).clamp(
    8.0,
    constraints.maxWidth - 64,
  );
  final tailTop = (fittedRect.top + 8).clamp(8.0, constraints.maxHeight - 40);
  final resolvedOffset = currentOffset ?? Offset(tailLeft, tailTop);
  final tailWidth = isPopupVisible ? 248.0 : 56.0;
  final tailHeight = isPopupVisible ? 300.0 : 36.0;
  return Offset(
    resolvedOffset.dx.clamp(8.0, constraints.maxWidth - tailWidth),
    resolvedOffset.dy.clamp(8.0, constraints.maxHeight - tailHeight),
  );
}

class RemoteSessionScaffold extends StatelessWidget {
  const RemoteSessionScaffold({
    super.key,
    required this.onCloseSession,
    required this.onBackPressed,
    required this.builder,
  });

  final VoidCallback onCloseSession;
  final VoidCallback onBackPressed;
  final Widget Function(BuildContext context, BoxConstraints constraints)
  builder;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          onBackPressed();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          minimum: EdgeInsets.only(
            bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: LayoutBuilder(builder: builder),
          ),
        ),
      ),
    );
  }
}

class RemoteSessionViewport extends StatelessWidget {
  const RemoteSessionViewport({
    super.key,
    required this.frameStream,
    required this.displayRect,
    required this.remoteCaptureSize,
    required this.remoteScreenSize,
    required this.useTrajectorySwipe,
    required this.useAnnotationMode,
    required this.initialSps,
    required this.initialPps,
    required this.latestSpsProvider,
    required this.latestPpsProvider,
    required this.onViewerReady,
    required this.onGesture,
    required this.onAnnotationCircle,
    required this.onInteraction,
  });

  final Stream<ScreenFrame> frameStream;
  final Rect displayRect;
  final Size remoteCaptureSize;
  final Size remoteScreenSize;
  final bool useTrajectorySwipe;
  final bool useAnnotationMode;
  final Uint8List? initialSps;
  final Uint8List? initialPps;
  final Uint8List? Function() latestSpsProvider;
  final Uint8List? Function() latestPpsProvider;
  final Future<void> Function() onViewerReady;
  final ValueChanged<protocol.GestureCommand> onGesture;
  final RemoteAnnotationCircleCallback onAnnotationCircle;
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
                useTrajectorySwipe: useTrajectorySwipe,
                useAnnotationMode: useAnnotationMode,
                onGesture: onGesture,
                onAnnotationCircle: onAnnotationCircle,
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

class RemoteOverlayTextSheet extends StatelessWidget {
  const RemoteOverlayTextSheet({
    super.key,
    required this.controller,
    required this.onSendText,
  });

  final TextEditingController controller;
  final Future<void> Function(String text) onSendText;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.text_fields_rounded,
                      color: Color(0xFFC4B5FD),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '发送文字提示到被控端',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(color: Colors.white, height: 1.35),
                decoration: InputDecoration(
                  hintText: '输入要显示在被控端屏幕上方的文字',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                      color: Color(0xFFC4B5FD),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => onSendText(controller.text),
                icon: const Icon(Icons.send_rounded),
                label: const Text('发送提示'),
              ),
            ],
          ),
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
