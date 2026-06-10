import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/remote_control_protocol.dart' as protocol;
import '../services/screen_capture_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/remote_control_gesture_overlay.dart';
import '../widgets/remote_control_screen_viewer.dart';

part 'remote_control_session_tail_widgets.dart';
part 'remote_control_session_text_sheets.dart';
part 'remote_control_session_keyboard_sheet.dart';

Rect computeRemoteSessionFittedRect(Size viewportSize, Size remoteSize) {
  final widthScale = viewportSize.width / remoteSize.width;
  final heightScale = viewportSize.height / remoteSize.height;
  final scale = widthScale < heightScale ? widthScale : heightScale;
  final fittedWidth = remoteSize.width * scale;
  final fittedHeight = remoteSize.height * scale;
  final left = (viewportSize.width - fittedWidth) / 2;
  final top = (viewportSize.height - fittedHeight) / 2;
  return Rect.fromLTWH(left, top, fittedWidth, fittedHeight);
}

Offset resolveRemoteTailOffset({
  required Rect fittedRect,
  required BoxConstraints constraints,
  required Offset? currentOffset,
  required bool isPopupVisible,
}) {
  final tailLeft = (fittedRect.center.dx - 28).clamp(
    8.0,
    constraints.maxWidth - 64,
  );
  final tailTop = (fittedRect.top + 8).clamp(8.0, constraints.maxHeight - 40);
  final resolvedOffset = currentOffset ?? Offset(tailLeft, tailTop);
  final tailWidth = isPopupVisible ? 248.0 : 56.0;
  final tailHeight = isPopupVisible ? 300.0 : 36.0;
  return Offset(
    resolvedOffset.dx.clamp(8.0, constraints.maxWidth - tailWidth),
    resolvedOffset.dy.clamp(8.0, constraints.maxHeight - tailHeight),
  );
}

class RemoteSessionScaffold extends StatelessWidget {
  const RemoteSessionScaffold({
    super.key,
    required this.onCloseSession,
    required this.onBackPressed,
    required this.builder,
  });

  final VoidCallback onCloseSession;
  final VoidCallback onBackPressed;
  final Widget Function(BuildContext context, BoxConstraints constraints)
  builder;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          onBackPressed();
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
            child: LayoutBuilder(builder: builder),
          ),
        ),
      ),
    );
  }
}

class RemoteSessionViewport extends StatelessWidget {
  const RemoteSessionViewport({
    super.key,
    required this.frameStream,
    required this.displayRect,
    required this.remoteCaptureSize,
    required this.remoteScreenSize,
    required this.useTrajectorySwipe,
    required this.useAnnotationMode,
    required this.initialSps,
    required this.initialPps,
    required this.latestSpsProvider,
    required this.latestPpsProvider,
    required this.onViewerReady,
    required this.onGesture,
    required this.onAnnotationCircle,
    required this.onInteraction,
  });

  final Stream<ScreenFrame> frameStream;
  final Rect displayRect;
  final Size remoteCaptureSize;
  final Size remoteScreenSize;
  final bool useTrajectorySwipe;
  final bool useAnnotationMode;
  final Uint8List? initialSps;
  final Uint8List? initialPps;
  final Uint8List? Function() latestSpsProvider;
  final Uint8List? Function() latestPpsProvider;
  final Future<void> Function() onViewerReady;
  final ValueChanged<protocol.GestureCommand> onGesture;
  final RemoteAnnotationCircleCallback onAnnotationCircle;
  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: displayRect.left,
      top: displayRect.top,
      width: displayRect.width,
      height: displayRect.height,
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
                  '${remoteCaptureSize.width}x${remoteCaptureSize.height}',
                ),
                onViewerReady: onViewerReady,
                frameStream: frameStream,
                remoteScreenSize: remoteCaptureSize,
                initialSps: initialSps,
                initialPps: initialPps,
                latestSpsProvider: latestSpsProvider,
                latestPpsProvider: latestPpsProvider,
              ),
              RemoteControlGestureOverlay(
                displayScreenSize: remoteCaptureSize,
                targetScreenSize: remoteScreenSize,
                useTrajectorySwipe: useTrajectorySwipe,
                useAnnotationMode: useAnnotationMode,
                onGesture: onGesture,
                onAnnotationCircle: onAnnotationCircle,
                onInteraction: onInteraction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
