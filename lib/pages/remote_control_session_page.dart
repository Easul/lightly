import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../services/remote_control_protocol.dart' as protocol;
import '../services/remote_control_protocol.dart' show GlobalAction;
import '../services/remote_control_service.dart';
import '../theme/app_theme.dart';
import '../widgets/remote_control_gesture_overlay.dart';
import '../widgets/remote_control_screen_viewer.dart';

class RemoteControlSessionPage extends StatefulWidget {
  final RemoteControlService service;
  final String remoteHost;

  const RemoteControlSessionPage({
    super.key,
    required this.service,
    required this.remoteHost,
  });

  @override
  State<RemoteControlSessionPage> createState() =>
      _RemoteControlSessionPageState();
}

class _RemoteControlSessionPageState extends State<RemoteControlSessionPage> {
  static const int _remoteDeleteKeyCode = 67;
  static const int _remoteEnterKeyCode = 66;
  static const int _remoteSpaceKeyCode = 62;
  static const int _remoteTabKeyCode = 61;

  late StreamSubscription<RemoteControlState> _stateSubscription;
  late StreamSubscription<protocol.ControlMessage> _messageSubscription;
  Size _remoteScreenSize = const Size(1080, 2340);
  Size _remoteCaptureSize = const Size(1080, 2340);
  bool _isAudioEnabled = false;
  bool _isControlsVisible = true;
  bool _isActionPopupVisible = false;
  Offset? _tailOffset;
  bool _isClosingSession = false;

  @override
  void initState() {
    super.initState();
    _remoteScreenSize =
        widget.service.latestRemoteScreenSize ?? _remoteScreenSize;
    _remoteCaptureSize = _remoteScreenSize;
    _isAudioEnabled = widget.service.audioCaptureService.isCapturing;
    _stateSubscription = widget.service.stateStream.listen(_handleStateChange);
    _messageSubscription = widget.service.messageStream.listen(_handleMessage);
  }

  @override
  void dispose() {
    if (!_isClosingSession) {
      unawaited(widget.service.disconnect());
    }
    _stateSubscription.cancel();
    _messageSubscription.cancel();
    super.dispose();
  }

  void _handleStateChange(RemoteControlState state) {
    if (state == RemoteControlState.disconnected && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('连接已断开')));
    }
  }

  void _handleGesture(protocol.GestureCommand command) {
    widget.service.sendGesture(command);
  }

  void _handleGlobalAction(String action) {
    switch (action) {
      case 'back':
        widget.service.sendGlobalAction(GlobalAction.back);
        break;
      case 'home':
        widget.service.sendGlobalAction(GlobalAction.home);
        break;
      case 'recents':
        widget.service.sendGlobalAction(GlobalAction.recents);
        break;
    }
  }

  Future<void> _toggleAudio() async {
    if (_isAudioEnabled) {
      await widget.service.stopAudioCapture();
      setState(() => _isAudioEnabled = false);
    } else {
      final success = await widget.service.startAudioCapture();
      if (success) {
        setState(() => _isAudioEnabled = true);
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法启动语音，请检查权限')));
      }
    }
  }

  Future<void> _requestKeyFrame() async {
    await widget.service.requestKeyFrame();
  }

  Future<void> _closeSession() async {
    if (_isClosingSession) {
      return;
    }
    _isClosingSession = true;
    await widget.service.stopAudioCapture();
    await widget.service.disconnect();
    if (mounted) Navigator.pop(context);
  }

  void _handleRemoteSurfaceInteraction() {
    if (!_isControlsVisible && !_isActionPopupVisible) {
      return;
    }
    setState(() {
      _isControlsVisible = false;
      _isActionPopupVisible = false;
    });
  }

  void _restoreControls() {
    if (_isControlsVisible && !_isActionPopupVisible) {
      return;
    }
    setState(() {
      _isControlsVisible = true;
      _isActionPopupVisible = false;
    });
  }

  void _toggleTailPopup() {
    setState(() {
      _isControlsVisible = true;
      _isActionPopupVisible = !_isActionPopupVisible;
    });
  }

  void _moveTail(DragUpdateDetails details, Size viewportSize) {
    final current = _tailOffset ?? Offset(viewportSize.width / 2 - 28, 12);
    final next = current + details.delta;
    final tailWidth = _isActionPopupVisible ? 248.0 : 56.0;
    final tailHeight = _isActionPopupVisible ? 220.0 : 36.0;
    final maxLeft = (viewportSize.width - tailWidth).clamp(
      8.0,
      viewportSize.width,
    );
    final maxTop = (viewportSize.height - tailHeight).clamp(
      8.0,
      viewportSize.height,
    );
    setState(() {
      _tailOffset = Offset(
        next.dx.clamp(8.0, maxLeft),
        next.dy.clamp(8.0, maxTop),
      );
    });
  }

  Future<void> _sendKeyboardText(String text) async {
    if (text.isEmpty) return;
    await widget.service.sendKeyboard(
      protocol.KeyboardCommand.text(text: text),
    );
  }

  Future<void> _sendKeyboardKey(int keyCode) async {
    await widget.service.sendKeyboard(
      protocol.KeyboardCommand.key(keyCode: keyCode),
    );
  }

  Future<void> _showKeyboardSheet() async {
    final controller = TextEditingController();
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF111827),
        builder: (context) {
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
                    await _sendKeyboardText(value);
                    controller.clear();
                  },
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    return FilledButton.icon(
                      onPressed: value.text.isEmpty
                          ? null
                          : () async {
                              await _sendKeyboardText(value.text);
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
                    _KeyboardQuickActionChip(
                      icon: Icons.space_bar_rounded,
                      label: '空格',
                      onTap: () => _sendKeyboardKey(_remoteSpaceKeyCode),
                    ),
                    _KeyboardQuickActionChip(
                      icon: Icons.keyboard_return_rounded,
                      label: '回车',
                      onTap: () => _sendKeyboardKey(_remoteEnterKeyCode),
                    ),
                    _KeyboardQuickActionChip(
                      icon: Icons.backspace_outlined,
                      label: '退格',
                      onTap: () => _sendKeyboardKey(_remoteDeleteKeyCode),
                    ),
                    _KeyboardQuickActionChip(
                      icon: Icons.keyboard_tab_rounded,
                      label: 'Tab',
                      onTap: () => _sendKeyboardKey(_remoteTabKeyCode),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  void _handleMessage(protocol.ControlMessage message) {
    if (message is protocol.StatusMessage && message.action == 'screen_info') {
      final width = (message.data['width'] as num?)?.toDouble();
      final height = (message.data['height'] as num?)?.toDouble();
      final captureWidth = (message.data['captureWidth'] as num?)?.toDouble();
      final captureHeight = (message.data['captureHeight'] as num?)?.toDouble();
      if (width == null || height == null || width <= 0 || height <= 0) {
        return;
      }

      final nextSize = Size(width, height);
      final nextCaptureSize =
          captureWidth != null &&
              captureHeight != null &&
              captureWidth > 0 &&
              captureHeight > 0
          ? Size(captureWidth, captureHeight)
          : nextSize;
      if (!mounted ||
          (nextSize == _remoteScreenSize &&
              nextCaptureSize == _remoteCaptureSize)) {
        return;
      }

      setState(() {
        _remoteScreenSize = nextSize;
        _remoteCaptureSize = nextCaptureSize;
      });
      unawaited(_requestKeyFrame());
      developer.log(
        'Updated remote screen size to ${width.toInt()}x${height.toInt()} capture=${nextCaptureSize.width.toInt()}x${nextCaptureSize.height.toInt()}',
        name: 'RemoteControl',
      );
      return;
    }

    developer.log('Received message: ${message.type}', name: 'RemoteControl');
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _closeSession();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final fittedRect = _computeFittedRect(
                  constraints.biggest,
                  _remoteCaptureSize,
                );
                final tailLeft = (fittedRect.center.dx - 28).clamp(
                  8.0,
                  constraints.maxWidth - 64,
                );
                final tailTop = (fittedRect.top + 8).clamp(
                  8.0,
                  constraints.maxHeight - 40,
                );
                final resolvedTailOffset =
                    _tailOffset ?? Offset(tailLeft, tailTop);
                final tailWidth = _isActionPopupVisible ? 248.0 : 56.0;
                final tailHeight = _isActionPopupVisible ? 220.0 : 36.0;
                final clampedTailOffset = Offset(
                  resolvedTailOffset.dx.clamp(
                    8.0,
                    constraints.maxWidth - tailWidth,
                  ),
                  resolvedTailOffset.dy.clamp(
                    8.0,
                    constraints.maxHeight - tailHeight,
                  ),
                );

                return Stack(
                  children: [
                    Positioned(
                      left: fittedRect.left,
                      top: fittedRect.top,
                      width: fittedRect.width,
                      height: fittedRect.height,
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
                                  '${_remoteCaptureSize.width}x${_remoteCaptureSize.height}',
                                ),
                                onViewerReady: _requestKeyFrame,
                                frameStream: widget.service.screenFrameStream,
                                remoteScreenSize: _remoteCaptureSize,
                                initialSps: widget.service.latestScreenSps,
                                initialPps: widget.service.latestScreenPps,
                                latestSpsProvider: () =>
                                    widget.service.latestScreenSps,
                                latestPpsProvider: () =>
                                    widget.service.latestScreenPps,
                              ),
                              RemoteControlGestureOverlay(
                                displayScreenSize: _remoteCaptureSize,
                                targetScreenSize: _remoteScreenSize,
                                onGesture: _handleGesture,
                                onInteraction: _handleRemoteSurfaceInteraction,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_isControlsVisible || _isActionPopupVisible)
                      Positioned(
                        left: clampedTailOffset.dx,
                        top: clampedTailOffset.dy,
                        child: _FloatingTailControls(
                          remoteHost: widget.remoteHost,
                          isAudioEnabled: _isAudioEnabled,
                          isReceiverMode:
                              widget.service.mode == RemoteControlMode.receiver,
                          isPopupVisible: _isActionPopupVisible,
                          onTailTap: _toggleTailPopup,
                          onTailDragUpdate: (details) =>
                              _moveTail(details, constraints.biggest),
                          onAudioTap: _toggleAudio,
                          onKeyboardTap: _showKeyboardSheet,
                          onRefreshTap: _requestKeyFrame,
                          onBackTap: () => _handleGlobalAction('back'),
                          onHomeTap: () => _handleGlobalAction('home'),
                          onRecentsTap: () => _handleGlobalAction('recents'),
                          onCloseTap: _closeSession,
                        ),
                      )
                    else
                      Positioned(
                        top: clampedTailOffset.dy,
                        left: clampedTailOffset.dx,
                        child: _HiddenTailHandle(
                          onTap: _restoreControls,
                          onDragUpdate: (details) =>
                              _moveTail(details, constraints.biggest),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Rect _computeFittedRect(Size viewportSize, Size remoteSize) {
    final widthScale = viewportSize.width / remoteSize.width;
    final heightScale = viewportSize.height / remoteSize.height;
    final scale = widthScale < heightScale ? widthScale : heightScale;
    final fittedWidth = remoteSize.width * scale;
    final fittedHeight = remoteSize.height * scale;
    final left = (viewportSize.width - fittedWidth) / 2;
    final top = (viewportSize.height - fittedHeight) / 2;
    return Rect.fromLTWH(left, top, fittedWidth, fittedHeight);
  }
}

class _FloatingTailControls extends StatelessWidget {
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

  const _FloatingTailControls({
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
                          _TailActionChip(
                            icon: audioIcon,
                            label: audioLabel,
                            accentColor: audioAccentColor,
                            onTap: onAudioTap,
                          ),
                          _TailActionChip(
                            icon: Icons.keyboard_alt_outlined,
                            label: '键盘',
                            accentColor: const Color(0xFF2563EB),
                            onTap: onKeyboardTap,
                          ),
                          _TailActionChip(
                            icon: Icons.refresh,
                            label: '刷新',
                            accentColor: const Color(0xFF2563EB),
                            onTap: onRefreshTap,
                          ),
                          _TailActionChip(
                            icon: Icons.arrow_back,
                            label: '返回',
                            accentColor: const Color(0xFF4B5563),
                            onTap: onBackTap,
                          ),
                          _TailActionChip(
                            icon: Icons.home_rounded,
                            label: 'Home',
                            accentColor: const Color(0xFF4B5563),
                            onTap: onHomeTap,
                          ),
                          _TailActionChip(
                            icon: Icons.apps_rounded,
                            label: '最近',
                            accentColor: const Color(0xFF4B5563),
                            onTap: onRecentsTap,
                          ),
                          _TailActionChip(
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

class _TailActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  const _TailActionChip({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

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

class _HiddenTailHandle extends StatelessWidget {
  final VoidCallback onTap;
  final ValueChanged<DragUpdateDetails> onDragUpdate;

  const _HiddenTailHandle({required this.onTap, required this.onDragUpdate});

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

class _KeyboardQuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _KeyboardQuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

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
