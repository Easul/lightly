import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppToast {
  AppToast._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static OverlayEntry? _entry;
  static GlobalKey<_AppToastOverlayState>? _overlayKey;

  static Future<void> show(
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) async {
    if (message.trim().isEmpty) {
      return;
    }

    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      return;
    }

    final existingKey = _overlayKey;
    if (existingKey?.currentState != null) {
      await existingKey!.currentState!.dismiss(replaced: true);
    }
    _entry?.remove();
    _entry = null;

    final key = GlobalKey<_AppToastOverlayState>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _AppToastOverlay(
        key: key,
        message: message,
        duration: duration,
        onDismissed: () {
          if (_entry == entry) {
            _entry?.remove();
            _entry = null;
            _overlayKey = null;
          }
        },
      ),
    );

    _overlayKey = key;
    _entry = entry;
    overlay.insert(entry);
  }
}

class _AppToastOverlay extends StatefulWidget {
  const _AppToastOverlay({
    super.key,
    required this.message,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_AppToastOverlay> createState() => _AppToastOverlayState();
}

class _AppToastOverlayState extends State<_AppToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 140),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<Offset> _slide =
      Tween<Offset>(begin: const Offset(0, -0.18), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      );
  Timer? _dismissTimer;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.forward());
    _dismissTimer = Timer(widget.duration, () {
      unawaited(dismiss());
    });
  }

  Future<void> dismiss({bool replaced = false}) async {
    if (_dismissed) {
      return;
    }
    _dismissed = true;
    _dismissTimer?.cancel();
    if (replaced) {
      _controller.reverseDuration = const Duration(milliseconds: 90);
    }
    await _controller.reverse();
    if (mounted) {
      widget.onDismissed();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final maxWidth = (mediaQuery.size.width - 32).clamp(180.0, 320.0);

    return Positioned(
      top: mediaQuery.viewPadding.top + 14,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _fade,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.96,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colorScheme.primaryContainer),
                    boxShadow: AppTheme.softShadow(0.10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: colorScheme.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          widget.message,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
