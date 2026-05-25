import 'dart:async';

import 'package:flutter/material.dart';

import '../services/remote_control_protocol.dart' as protocol;
import '../services/remote_control_protocol.dart' show GlobalAction;
import '../services/remote_control_service.dart';
import '../services/app_toast.dart';
import 'remote_control_session_widgets.dart';

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

  void _showToast(String message) {
    unawaited(AppToast.show(message));
  }

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
      _showToast('连接已断开');
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
        _showToast('无法启动语音，请检查权限');
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
        builder: (context) => RemoteKeyboardSheet(
          controller: controller,
          onSendText: _sendKeyboardText,
          onSpace: () => unawaited(_sendKeyboardKey(_remoteSpaceKeyCode)),
          onEnter: () => unawaited(_sendKeyboardKey(_remoteEnterKeyCode)),
          onDelete: () => unawaited(_sendKeyboardKey(_remoteDeleteKeyCode)),
          onTab: () => unawaited(_sendKeyboardKey(_remoteTabKeyCode)),
        ),
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
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_closeSession());
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
                    RemoteSessionViewport(
                      displayRect: fittedRect,
                      frameStream: widget.service.screenFrameStream,
                      remoteCaptureSize: _remoteCaptureSize,
                      remoteScreenSize: _remoteScreenSize,
                      initialSps: widget.service.latestScreenSps,
                      initialPps: widget.service.latestScreenPps,
                      latestSpsProvider: () => widget.service.latestScreenSps,
                      latestPpsProvider: () => widget.service.latestScreenPps,
                      onViewerReady: _requestKeyFrame,
                      onGesture: _handleGesture,
                      onInteraction: _handleRemoteSurfaceInteraction,
                    ),
                    if (_isControlsVisible || _isActionPopupVisible)
                      Positioned(
                        left: clampedTailOffset.dx,
                        top: clampedTailOffset.dy,
                        child: FloatingTailControls(
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
                        child: HiddenTailHandle(
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
