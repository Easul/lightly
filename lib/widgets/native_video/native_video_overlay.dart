import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class NativeVideoOverlay extends StatefulWidget {
  const NativeVideoOverlay({
    super.key,
    required this.chewieController,
    required this.compact,
    required this.resolvedTitle,
    required this.onDownload,
    this.onClose,
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
  final VoidCallback? onClose;
  final ValueListenable<String?> gestureHintNotifier;
  final GestureDragStartCallback onVerticalDragStart;
  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;
  final VoidCallback onVerticalDragCancel;

  @override
  State<NativeVideoOverlay> createState() => _NativeVideoOverlayState();
}

class _NativeVideoOverlayState extends State<NativeVideoOverlay> {
  Timer? _controlsTimer;
  bool _overlayControlsVisible = true;

  @override
  void initState() {
    super.initState();
    _showOverlayControlsTemporarily();
  }

  void _showOverlayControlsTemporarily() {
    setState(() => _overlayControlsVisible = true);
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _overlayControlsVisible = false);
      }
    });
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _showOverlayControlsTemporarily,
              onVerticalDragStart: widget.onVerticalDragStart,
              onVerticalDragUpdate: widget.onVerticalDragUpdate,
              onVerticalDragEnd: widget.onVerticalDragEnd,
              onVerticalDragCancel: widget.onVerticalDragCancel,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Chewie(controller: widget.chewieController),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: AnimatedOpacity(
                      opacity: _overlayControlsVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: IgnorePointer(
                        ignoring: !_overlayControlsVisible,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Material(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(20),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.download_rounded,
                                  color: Colors.white,
                                ),
                                tooltip: '下载视频',
                                onPressed: widget.onDownload,
                              ),
                            ),
                            if (widget.onClose != null) ...[
                              const SizedBox(width: 8),
                              Material(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: const CircleBorder(),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                  ),
                                  tooltip: '关闭',
                                  onPressed: widget.onClose,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (widget.resolvedTitle != null && widget.compact)
                    Positioned(
                      left: 12,
                      top: 12,
                      right: 12,
                      child: Text(
                        widget.resolvedTitle!,
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
              valueListenable: widget.gestureHintNotifier,
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
