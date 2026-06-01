enum NativeVideoGestureControlSide { brightness, volume }

class NativeVideoGestureAction {
  const NativeVideoGestureAction({
    required this.side,
    required this.nextValue,
    required this.hint,
  });

  final NativeVideoGestureControlSide side;
  final double nextValue;
  final String hint;
}

class NativeVideoGestureController {
  NativeVideoGestureControlSide? _side;
  double _currentValue = 0.5;

  void startGesture({
    required double localDx,
    required double maxWidth,
    required double brightness,
    required double volume,
  }) {
    final isLeft = localDx < maxWidth / 2;
    _side = isLeft
        ? NativeVideoGestureControlSide.brightness
        : NativeVideoGestureControlSide.volume;
    _currentValue = isLeft ? brightness : volume;
  }

  NativeVideoGestureAction? updateGesture({
    required double primaryDelta,
    required double sensitivity,
  }) {
    final side = _side;
    if (side == null) {
      return null;
    }

    final delta = -primaryDelta / sensitivity;
    final nextValue = (_currentValue + delta).clamp(0.0, 1.0);
    _currentValue = nextValue;
    final percent = (nextValue * 100).round();
    final hint = side == NativeVideoGestureControlSide.brightness
        ? '亮度 $percent%'
        : '音量 $percent%';
    return NativeVideoGestureAction(
      side: side,
      nextValue: nextValue,
      hint: hint,
    );
  }

  void endGesture() {
    _side = null;
  }
}
