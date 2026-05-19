import 'dart:async';

import 'package:flutter/material.dart';

/// A draggable floating circular button overlay.
///
/// After 10 seconds of inactivity (no tap or drag), the button fades to 20%
/// opacity and shrinks to half its radius. Any tap or drag resets the idle
/// timer and restores full appearance. A tap while in the idle state only
/// restores appearance; a tap while already visible triggers [onTap].
class FloatingButtonOverlay extends StatefulWidget {
  const FloatingButtonOverlay({
    super.key,
    required this.onTap,
    this.onExit,
    this.icon = Icons.language,
    this.initialOffset = const Offset(20, 200),
    this.screenSize = Size.zero,
  });

  final VoidCallback onTap;
  final VoidCallback? onExit;
  final IconData icon;
  final Offset initialOffset;
  final Size screenSize;

  @override
  State<FloatingButtonOverlay> createState() => _FloatingButtonOverlayState();
}

class _FloatingButtonOverlayState extends State<FloatingButtonOverlay>
    with SingleTickerProviderStateMixin {
  static const double _normalRadius = 28.0;
  static const double _idleRadius = 14.0;
  static const Duration _idleTimeout = Duration(seconds: 10);
  static const Duration _animationDuration = Duration(milliseconds: 300);

  Offset _position = Offset.zero;
  double _radius = _normalRadius;
  double _opacity = 1.0;
  bool _isIdle = false;
  Timer? _idleTimer;

  late final AnimationController _controller;
  late final Animation<double> _radiusAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _position = widget.initialOffset;

    _controller = AnimationController(
      vsync: this,
      duration: _animationDuration,
    );

    _radiusAnimation = Tween<double>(
      begin: _normalRadius,
      end: _idleRadius,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _radiusAnimation.addListener(_onAnimationTick);
    _opacityAnimation.addListener(_onAnimationTick);

    _resetIdleTimer();
  }

  void _onAnimationTick() {
    if (mounted) {
      setState(() {
        _radius = _radiusAnimation.value;
        _opacity = _opacityAnimation.value;
      });
    }
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, _enterIdle);
  }

  void _enterIdle() {
    if (!mounted || _isIdle) return;
    _isIdle = true;
    _controller.forward();
  }

  void _exitIdle() {
    if (!_isIdle) return;
    _isIdle = false;
    _controller.reverse();
    _resetIdleTimer();
  }

  void _onInteraction() {
    if (_isIdle) {
      // Tap/drag while idle → only restore appearance, don't trigger action.
      _exitIdle();
      return;
    }
    // Not idle → reset the idle countdown.
    _resetIdleTimer();
  }

  void _onTap() {
    if (_isIdle) {
      _exitIdle();
      return;
    }
    _resetIdleTimer();
    widget.onTap();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _radiusAnimation.removeListener(_onAnimationTick);
    _opacityAnimation.removeListener(_onAnimationTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FloatingButtonOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialOffset != oldWidget.initialOffset &&
        _position == oldWidget.initialOffset) {
      _position = widget.initialOffset;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned(
          left: _position.dx,
          top: _position.dy,
          child: GestureDetector(
            onPanStart: (_) => _onInteraction(),
            onPanUpdate: (details) {
              setState(() {
                _position = Offset(
                  (_position.dx + details.delta.dx).clamp(
                    0,
                    (widget.screenSize.width - _radius * 2).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                  (_position.dy + details.delta.dy).clamp(
                    0,
                    (widget.screenSize.height - _radius * 2).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                );
              });
              if (!_isIdle) {
                _resetIdleTimer();
              }
            },
            onPanEnd: (_) {
              if (_isIdle) {
                _exitIdle();
              } else {
                _resetIdleTimer();
              }
            },
            onTap: _onTap,
            child: Opacity(
              opacity: _opacity,
              child: Container(
                width: _radius * 2,
                height: _radius * 2,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  widget.icon,
                  color: colorScheme.onPrimary,
                  size: _radius * 0.9,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
