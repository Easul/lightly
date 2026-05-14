import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class NativeVideoOverlay extends StatelessWidget {
  const NativeVideoOverlay({
    super.key,
    required this.chewieController,
    required this.compact,
    required this.resolvedTitle,
    required this.onDownload,
    required this.gestureHintNotifier,
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    required this.onVerticalDragCancel,
  });

  final ChewieController chewieController;
  final bool compact;
  final String? resolvedTitle;
  final VoidCallback onDownload;
  final ValueListenable<String?> gestureHintNotifier;
  final GestureDragStartCallback onVerticalDragStart;
  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;
  final VoidCallback onVerticalDragCancel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragStart: onVerticalDragStart,
              onVerticalDragUpdate: onVerticalDragUpdate,
              onVerticalDragEnd: onVerticalDragEnd,
              onVerticalDragCancel: onVerticalDragCancel,
              child: Stack(
                children: [
                  Positioned.fill(child: Chewie(controller: chewieController)),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                      child: IconButton(
                        icon: const Icon(
                          Icons.download_rounded,
                          color: Colors.white,
                        ),
                        tooltip: '下载视频',
                        onPressed: onDownload,
                      ),
                    ),
                  ),
                  if (resolvedTitle != null && compact)
                    Positioned(
                      left: 12,
                      top: 12,
                      right: 12,
                      child: Text(
                        resolvedTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<String?>(
              valueListenable: gestureHintNotifier,
              builder: (context, gestureHint, child) {
                if (gestureHint == null) {
                  return const SizedBox.shrink();
                }
                return Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      gestureHint,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
