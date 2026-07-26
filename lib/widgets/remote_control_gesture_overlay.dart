import 'package:flutter/material.dart';
import '../features/remote_control/domain/remote_control_protocol.dart'
    as protocol;

typedef RemoteAnnotationCircleCallback =
    void Function({
      required double centerX,
      required double centerY,
      required double radius,
    });

@visibleForTesting
Paint createSwipeTrailPaint() {
  return Paint()
    ..color = Colors.blue.withValues(alpha: 0.3)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.0
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
}

@visibleForTesting
Paint createAnnotationTrailPaint() {
  return Paint()
    ..color = const Color(0xFFFACC15).withValues(alpha: 0.78)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
}

class RemoteControlGestureOverlay extends StatefulWidget {
  final Function(protocol.GestureCommand)? onGesture;
  final RemoteAnnotationCircleCallback? onAnnotationCircle;
  final Size displayScreenSize;
  final Size targetScreenSize;
  final VoidCallback? onInteraction;
  final bool useTrajectorySwipe;
  final bool useAnnotationMode;

  const RemoteControlGestureOverlay({
    super.key,
    this.onGesture,
    this.onAnnotationCircle,
    required this.displayScreenSize,
    required this.targetScreenSize,
    this.onInteraction,
    this.useTrajectorySwipe = false,
    this.useAnnotationMode = false,
  });

  @override
  State<RemoteControlGestureOverlay> createState() =>
      _RemoteControlGestureOverlayState();
}

class _RemoteControlGestureOverlayState
    extends State<RemoteControlGestureOverlay> {
  Offset? _panStart;
  Offset? _panCurrent;
  final List<Offset> _panPoints = <Offset>[];
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
      _panPoints
        ..clear()
        ..add(clamped);
      _isPanning = false;
      _touchStartTime = DateTime.now();
    });
  }

  void _resetGestureState() {
    if (!mounted) return;
    setState(() {
      _panStart = null;
      _panCurrent = null;
      _panPoints.clear();
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
      if (_panPoints.isEmpty ||
          (nextPosition - _panPoints.last).distance >= 6.0) {
        _panPoints.add(nextPosition);
      }
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

    if (widget.useAnnotationMode) {
      if (_annotationPathDistance(localPos) >= _swipeMinDistance) {
        _sendAnnotationCircle(localPos, widgetSize);
      }
    } else if (_isPanning && distance >= _swipeMinDistance) {
      final start = _scaleToLocal(_panStart!, widgetSize);
      final end = _scaleToLocal(localPos, widgetSize);
      final swipeDurationMs = duration.inMilliseconds.clamp(90, 220);
      if (widget.useTrajectorySwipe) {
        final rawPoints = <Offset>[
          if (_panPoints.isEmpty) _panStart! else ..._panPoints,
          localPos,
        ];
        final points = rawPoints
            .map((point) => _scaleToLocal(point, widgetSize))
            .map((point) => protocol.OffsetPoint(x: point.dx, y: point.dy))
            .toList();
        widget.onGesture?.call(
          protocol.GestureCommand.trajectory(
            points: points,
            duration: duration.inMilliseconds.clamp(180, 900),
          ),
        );
      } else {
        widget.onGesture?.call(
          protocol.GestureCommand.swipe(
            startX: start.dx,
            startY: start.dy,
            endX: end.dx,
            endY: end.dy,
            duration: swipeDurationMs,
          ),
        );
      }
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

  double _annotationPathDistance(Offset localPos) {
    final bounds = _boundsForPoints(<Offset>[
      if (_panPoints.isEmpty) _panStart! else ..._panPoints,
      localPos,
    ]);
    return bounds.width > bounds.height ? bounds.width : bounds.height;
  }

  void _sendAnnotationCircle(Offset localPos, Size widgetSize) {
    final rawPoints = <Offset>[
      if (_panPoints.isEmpty) _panStart! else ..._panPoints,
      localPos,
    ];
    final points = rawPoints.map((point) => _scaleToLocal(point, widgetSize));
    final bounds = _boundsForPoints(points);
    if (bounds == Rect.zero) {
      return;
    }
    final radius =
        (bounds.width > bounds.height ? bounds.width : bounds.height) / 2;
    if (radius <= 0) return;
    widget.onAnnotationCircle?.call(
      centerX: bounds.center.dx,
      centerY: bounds.center.dy,
      radius: radius,
    );
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
                  painter: widget.useAnnotationMode
                      ? _AnnotationTrailPainter(
                          start: _panStart!,
                          current: _panCurrent!,
                          points: _panPoints,
                        )
                      : _SwipeTrailPainter(
                          start: _panStart!,
                          current: _panCurrent!,
                          points: _panPoints,
                        ),
                ),
              ),
          ],
        );
      },
    );
  }
}

Rect _boundsForPoints(Iterable<Offset> points) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final point in points) {
    minX = point.dx < minX ? point.dx : minX;
    minY = point.dy < minY ? point.dy : minY;
    maxX = point.dx > maxX ? point.dx : maxX;
    maxY = point.dy > maxY ? point.dy : maxY;
  }
  if (!minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite) {
    return Rect.zero;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

class _AnnotationTrailPainter extends CustomPainter {
  final Offset start;
  final Offset current;
  final List<Offset> points;

  _AnnotationTrailPainter({
    required this.start,
    required this.current,
    required this.points,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trailPaint = createAnnotationTrailPaint();
    final rawPoints = <Offset>[
      if (points.isEmpty) start else ...points,
      current,
    ];
    if (rawPoints.length > 1) {
      final path = Path()..moveTo(rawPoints.first.dx, rawPoints.first.dy);
      for (final point in rawPoints.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, trailPaint);
    } else {
      canvas.drawLine(start, current, trailPaint);
    }

    final rect = _boundsForPoints(rawPoints);
    if (rect.width > 0 || rect.height > 0) {
      final radius = (rect.width > rect.height ? rect.width : rect.height) / 2;
      final previewPaint = Paint()
        ..color = const Color(0xFFFACC15).withValues(alpha: 0.34)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(rect.center, radius, previewPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationTrailPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.current != current;
  }
}

class _SwipeTrailPainter extends CustomPainter {
  final Offset start;
  final Offset current;
  final List<Offset> points;

  _SwipeTrailPainter({
    required this.start,
    required this.current,
    required this.points,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = createSwipeTrailPaint();

    if (points.length > 1) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.lineTo(current.dx, current.dy);
      canvas.drawPath(path, paint);
    } else {
      canvas.drawLine(start, current, paint);
    }

    final circlePaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(start, 8, circlePaint);
    canvas.drawCircle(current, 8, circlePaint);
  }

  @override
  bool shouldRepaint(covariant _SwipeTrailPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.current != current;
  }
}
