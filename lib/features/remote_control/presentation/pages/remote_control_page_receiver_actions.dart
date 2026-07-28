part of 'remote_control_page.dart';

extension _RemoteControlPageReceiverActions on _RemoteControlPageState {
  Future<void> _startReceiver() async {
    if (!await widget.ensureEasyTierPluginAvailable()) {
      return;
    }
    if (!mounted) return;
    final effectiveNoTunMode = resolveReceiverNoTunMode(
      receiverNoTunMode: _useReceiverNoTunMode,
      p2pNoTunMode: _runtimeCoordinator.isEasyTierNoTunMode,
    );
    final voiceAvailable = effectiveNoTunMode
        ? false
        : await widget.ensureVoicePluginAvailable();
    if (!voiceAvailable && !effectiveNoTunMode && mounted) {
      _showToast('远程语音插件不可用，被控端将仅启用屏幕与控制功能');
    }
    if (!mounted) return;
    _updateState(() {
      _isConnecting = true;
      _useReceiverNoTunMode = effectiveNoTunMode;
      _errorMessage = null;
      _hadConnectedSession = false;
    });

    try {
      final ports = await _receiverHelper.startReceiverFlow(
        permissionRuntime: widget.platformRuntime,
        service: _service,
        ensureVpnForRemoteControl: ({bool noTunMode = false}) =>
            _runtimeCoordinator.ensureReceiverNetwork(noTunMode: noTunMode),
        useNoTunMode: effectiveNoTunMode,
        voicePluginAvailable: voiceAvailable,
      );

      if (!mounted) return;
      _updateState(() {
        _portConfig = ports;
        _isConnecting = false;
        _isReceiverRunning = true;
      });
      _applyPortConfigToInputs(ports);

      if (mounted) {
        _showToast('被控端已启动，端口: ${ports.controlPort}/${ports.screenPort}');
      }
    } on RemoteControlPageReceiverStartException catch (error) {
      if (!mounted) return;
      _showToast(error.message);
      _updateState(() => _isConnecting = false);
    } catch (e) {
      if (!mounted) return;
      _updateState(() {
        _isConnecting = false;
        _errorMessage = '启动失败: $e';
      });
    }
  }

  Future<void> _stopReceiver() async {
    _updateState(() {
      _isConnecting = true;
      _errorMessage = null;
    });
    try {
      await _runtimeCoordinator.shutdownAll();
      if (!mounted) return;
      _updateState(() {
        _isConnecting = false;
        _isReceiverRunning = false;
        _isReceiverAudioEnabled = false;
        _hadConnectedSession = false;
        _portConfig = null;
      });
      _applyPortConfigToInputs(null);
      _showToast('被控端已关闭');
    } catch (e) {
      if (!mounted) return;
      _updateState(() {
        _isConnecting = false;
        _errorMessage = '关闭失败: $e';
      });
    }
  }

  void _toggleReceiver() {
    if (_isReceiverRunning) {
      unawaited(_stopReceiver());
    } else {
      unawaited(_startReceiver());
    }
  }
}
