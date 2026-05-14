import 'package:flutter/material.dart';
import '../services/remote_control_protocol.dart' as protocol;

class RemoteControlGestureOverlay extends StatefulWidget {
  final Function(protocol.GestureCommand)? onGesture;
  final Size displayScreenSize;
  final Size targetScreenSize;
  final VoidCallback? onInteraction;

  const RemoteControlGestureOverlay({
    super.key,
    this.onGesture,
    required this.displayScreenSize,
    required this.targetScreenSize,
    this.onInteraction,
  });

  @override
  State<RemoteControlGestureOverlay> createState() =>
      _RemoteControlGestureOverlayState();
}

class _RemoteControlGestureOverlayState
    extends State<RemoteControlGestureOverlay> {
  Offset? _panStart;
  Offset? _panCurrent;
  bool _isPanning = false;
  DateTime? _touchStartTime;

  static const _longPressThreshold = Duration(milliseconds: 500);
  static const _swipeMinDistance = 12.0;

  Rect _computeContentRect(Size widgetSize) {
    if (widgetSize.width <= 0 || widgetSize.height <= 0) {
      return Rect.zero;
    }
    if (widget.displayScreenSize.width <= 0 ||
        widget.displayScreenSize.height <= 0) {
      return Offset.zero & widgetSize;
    }

    final widthScale = widgetSize.width / widget.displayScreenSize.width;
    final heightScale = widgetSize.height / widget.displayScreenSize.height;
    final scale = widthScale < heightScale ? widthScale : heightScale;
    final fittedWidth = widget.displayScreenSize.width * scale;
    final fittedHeight = widget.displayScreenSize.height * scale;
    final left = (widgetSize.width - fittedWidth) / 2;
    final top = (widgetSize.height - fittedHeight) / 2;
    return Rect.fromLTWH(left, top, fittedWidth, fittedHeight);
  }

  Offset _clampToWidgetBounds(Offset position, Size widgetSize) {
    if (widgetSize.width <= 0 || widgetSize.height <= 0) {
      return Offset.zero;
    }
    final safeDx = position.dx.isFinite
        ? position.dx.clamp(0.0, widgetSize.width)
        : 0.0;
    final safeDy = position.dy.isFinite
        ? position.dy.clamp(0.0, widgetSize.height)
        : 0.0;
    return Offset(safeDx, safeDy);
  }

  Offset _scaleToLocal(Offset globalPosition, Size widgetSize) {
    final contentRect = _computeContentRect(widgetSize);
    if (contentRect.width <= 0 || contentRect.height <= 0) {
      return Offset.zero;
    }
    final clamped = _clampToWidgetBounds(globalPosition, widgetSize);
    final localDx = (clamped.dx - contentRect.left).clamp(
      0.0,
      contentRect.width,
    );
    final localDy = (clamped.dy - contentRect.top).clamp(
      0.0,
      contentRect.height,
    );
    final normalizedX = localDx / contentRect.width;
    final normalizedY = localDy / contentRect.height;
    return Offset(
      normalizedX * widget.targetScreenSize.width,
      normalizedY * widget.targetScreenSize.height,
    );
  }

  void _onPointerDown(PointerDownEvent event, Size widgetSize) {
    widget.onInteraction?.call();
    final clamped = _clampToWidgetBounds(event.localPosition, widgetSize);
    setState(() {
      _panStart = clamped;
      _panCurrent = clamped;
      _isPanning = false;
      _touchStartTime = DateTime.now();
    });
  }

  void _resetGestureState() {
    if (!mounted) return;
    setState(() {
      _panStart = null;
      _panCurrent = null;
      _isPanning = false;
      _touchStartTime = null;
    });
  }

  void _onPointerMove(PointerMoveEvent event, Size widgetSize) {
    if (_panStart == null) return;

    final nextPosition = _clampToWidgetBounds(event.localPosition, widgetSize);
    final distance = (nextPosition - _panStart!).distance;

    setState(() {
      _panCurrent = nextPosition;
      if (distance > _swipeMinDistance) {
        _isPanning = true;
      }
    });
  }

  void _onPointerUp(PointerUpEvent event, Size widgetSize) {
    if (_panStart == null || _touchStartTime == null) return;

    final duration = DateTime.now().difference(_touchStartTime!);
    final localPos = _clampToWidgetBounds(event.localPosition, widgetSize);
    final distance = _panStart != null ? (localPos - _panStart!).distance : 0.0;

    if (_isPanning && distance >= _swipeMinDistance) {
      final start = _scaleToLocal(_panStart!, widgetSize);
      final end = _scaleToLocal(localPos, widgetSize);
      final swipeDurationMs = duration.inMilliseconds.clamp(90, 220);
      widget.onGesture?.call(
        protocol.GestureCommand.swipe(
          startX: start.dx,
          startY: start.dy,
          endX: end.dx,
          endY: end.dy,
          duration: swipeDurationMs,
        ),
      );
    } else if (duration >= _longPressThreshold) {
      final pos = _scaleToLocal(localPos, widgetSize);
      widget.onGesture?.call(
        protocol.GestureCommand.longPress(x: pos.dx, y: pos.dy),
      );
    } else {
      final pos = _scaleToLocal(localPos, widgetSize);
      widget.onGesture?.call(protocol.GestureCommand.tap(x: pos.dx, y: pos.dy));
    }

    _resetGestureState();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final widgetSize = Size(constraints.maxWidth, constraints.maxHeight);

        return Stack(
          children: [
            Listener(
              onPointerDown: (e) => _onPointerDown(e, widgetSize),
              onPointerMove: (e) => _onPointerMove(e, widgetSize),
              onPointerUp: (e) => _onPointerUp(e, widgetSize),
              onPointerCancel: (_) => _resetGestureState(),
              child: Container(color: Colors.transparent),
            ),
            if (_isPanning && _panStart != null && _panCurrent != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: _SwipeTrailPainter(
                    start: _panStart!,
                    current: _panCurrent!,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SwipeTrailPainter extends CustomPainter {
  final Offset start;
  final Offset current;

  _SwipeTrailPainter({required this.start, required this.current});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(start, current, paint);

    final circlePaint = Paint()
      ..color = Colors.blue.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(start, 8, circlePaint);
    canvas.drawCircle(current, 8, circlePaint);
  }

  @override
  bool shouldRepaint(covariant _SwipeTrailPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.current != current;
  }
}
