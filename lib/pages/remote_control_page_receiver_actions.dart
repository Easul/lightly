part of 'remote_control_page.dart';

extension _RemoteControlPageReceiverActions on _RemoteControlPageState {
  Future<void> _startReceiver() async {
    final effectiveNoTunMode = resolveReceiverNoTunMode(
      receiverNoTunMode: _useReceiverNoTunMode,
      p2pNoTunMode: _easyTierService.isNoTunMode,
    );
    _updateState(() {
      _isConnecting = true;
      _useReceiverNoTunMode = effectiveNoTunMode;
      _errorMessage = null;
      _hadConnectedSession = false;
    });

    try {
      final ports = await _receiverHelper.startReceiverFlow(
        platformGateway: _platformGateway,
        service: _service,
        ensureVpnForRemoteControl:
            AppLifecycleManager().ensureVpnForRemoteControl,
        useNoTunMode: effectiveNoTunMode,
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
      await AppLifecycleManager().shutdownAllServices();
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
