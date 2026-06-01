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
  bool _isVoiceEnabled = true;
  bool _isRemoteMicEnabled = false;
  bool _isControlsVisible = true;
  bool _isActionPopupVisible = false;
  Offset? _tailOffset;
  bool _isClosingSession = false;
  bool _disconnectDialogVisible = false;

  void _showToast(String message) {
    unawaited(AppToast.show(message));
  }

  @override
  void initState() {
    super.initState();
    _remoteScreenSize =
        widget.service.latestRemoteScreenSize ?? _remoteScreenSize;
    _remoteCaptureSize = _remoteScreenSize;
    _isAudioEnabled = widget.service.isLocalAudioEnabled;
    _isVoiceEnabled = widget.service.isVoiceEnabled;
    _isRemoteMicEnabled = widget.service.isRemoteMicrophoneEnabled;
    _stateSubscription = widget.service.stateStream.listen(_handleStateChange);
    _messageSubscription = widget.service.messageStream.listen(_handleMessage);
  }

  @override
  void dispose() {
    if (!_isClosingSession) {
      _isClosingSession = true;
      unawaited(widget.service.disconnect());
    }
    _stateSubscription.cancel();
    _messageSubscription.cancel();
    super.dispose();
  }

  void _handleStateChange(RemoteControlState state) {
    if (!mounted) {
      return;
    }
    if (!widget.service.isLocalDisconnectRequested &&
        (state == RemoteControlState.disconnected ||
            state == RemoteControlState.error)) {
      unawaited(_showDisconnectDialog(state));
    }
  }

  Future<void> _showDisconnectDialog(RemoteControlState state) async {
    if (_isClosingSession || _disconnectDialogVisible || !mounted) {
      return;
    }
    _disconnectDialogVisible = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('对方已断开'),
        content: Text(
          state == RemoteControlState.error
              ? '与 ${widget.remoteHost} 的连接异常中断。'
              : '对方已断开远程连接。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    _disconnectDialogVisible = false;
    if (!mounted) {
      return;
    }
    _isClosingSession = true;
    await widget.service.disconnect();
    if (mounted) {
      Navigator.pop(context);
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
    if (!_isVoiceEnabled) {
      _showToast('内置代理连接暂不支持语音');
      return;
    }
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

  Future<void> _toggleRemoteMicrophone() async {
    final enabled = !_isRemoteMicEnabled;
    await widget.service.setReceiverMicrophoneEnabled(enabled);
    if (mounted) {
      setState(() => _isRemoteMicEnabled = enabled);
    }
  }

  Future<void> _requestKeyFrame() async {
    await widget.service.refreshLatestRemoteFrame();
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

  Future<void> _showOverlayTextSheet() async {
    final controller = TextEditingController();
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF111827),
        builder: (context) => RemoteOverlayTextSheet(
          controller: controller,
          onSendText: (text) async {
            await widget.service.sendOverlayText(text);
            if (context.mounted) Navigator.pop(context);
          },
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
    if (message is protocol.StatusMessage &&
        message.action == 'receiver_microphone_status') {
      final enabled = message.data['enabled'] == true;
      if (mounted &&
          (enabled != _isRemoteMicEnabled ||
              (widget.service.mode == RemoteControlMode.receiver &&
                  enabled != _isAudioEnabled))) {
        setState(() {
          _isRemoteMicEnabled = enabled;
          if (widget.service.mode == RemoteControlMode.receiver) {
            _isAudioEnabled = enabled;
          }
        });
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RemoteSessionScaffold(
      onCloseSession: () => unawaited(_closeSession()),
      builder: (context, constraints) {
        final fittedRect = computeRemoteSessionFittedRect(
          constraints.biggest,
          _remoteCaptureSize,
        );
        final tailOffset = resolveRemoteTailOffset(
          fittedRect: fittedRect,
          constraints: constraints,
          currentOffset: _tailOffset,
          isPopupVisible: _isActionPopupVisible,
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
                left: tailOffset.dx,
                top: tailOffset.dy,
                child: FloatingTailControls(
                  remoteHost: widget.remoteHost,
                  isAudioEnabled: _isAudioEnabled,
                  isVoiceEnabled: _isVoiceEnabled,
                  isRemoteMicEnabled: _isRemoteMicEnabled,
                  isReceiverMode:
                      widget.service.mode == RemoteControlMode.receiver,
                  isPopupVisible: _isActionPopupVisible,
                  onTailTap: _toggleTailPopup,
                  onTailDragUpdate: (details) =>
                      _moveTail(details, constraints.biggest),
                  onAudioTap: _toggleAudio,
                  onRemoteMicTap: _toggleRemoteMicrophone,
                  onOverlayTextTap: _showOverlayTextSheet,
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
                top: tailOffset.dy,
                left: tailOffset.dx,
                child: HiddenTailHandle(
                  onTap: _restoreControls,
                  onDragUpdate: (details) =>
                      _moveTail(details, constraints.biggest),
                ),
              ),
          ],
        );
      },
    );
  }
}
