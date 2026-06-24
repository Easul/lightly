import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'floating_video_player.dart';

class FloatingVideoLoadingControls extends StatelessWidget {
  const FloatingVideoLoadingControls({
    super.key,
    required this.title,
    required this.mode,
    required this.isLocked,
    required this.isFullscreen,
    required this.isLooping,
    required this.modeToggleIcon,
    this.onClose,
    this.onDownload,
    this.onModeToggle,
    this.onLockToggle,
    this.onLoopToggle,
  });

  final String? title;
  final FloatingPlayerMode mode;
  final bool isLocked;
  final bool isFullscreen;
  final bool isLooping;
  final IconData modeToggleIcon;
  final VoidCallback? onClose;
  final VoidCallback? onDownload;
  final VoidCallback? onModeToggle;
  final VoidCallback? onLockToggle;
  final VoidCallback? onLoopToggle;

  double get _modeIconSize => mode == FloatingPlayerMode.mini ? 18 : 28;

  BoxConstraints get _modeButtonConstraints => mode == FloatingPlayerMode.mini
      ? const BoxConstraints(minWidth: 32, minHeight: 32)
      : const BoxConstraints(minWidth: 48, minHeight: 48);

  double get _titleFontSize => mode == FloatingPlayerMode.mini ? 12 : 14;

  @override
  Widget build(BuildContext context) {
    final displayTitle = FloatingVideoPlayer.shortDisplayTitle(title);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 4,
          left: 8,
          right: 8,
          child: Row(
            children: [
              if (displayTitle != null)
                Expanded(
                  child: Text(
                    displayTitle,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: _titleFontSize,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (onLockToggle != null && isFullscreen)
                _FloatingRoundIconButton(
                  margin: const EdgeInsets.only(left: 8),
                  icon: isLocked ? Icons.lock : Icons.lock_open,
                  size: _modeIconSize,
                  constraints: _modeButtonConstraints,
                  onPressed: onLockToggle,
                ),
              if (onLoopToggle != null)
                _FloatingLoopButton(
                  margin: const EdgeInsets.only(left: 8),
                  isLooping: isLooping,
                  compact: mode == FloatingPlayerMode.mini,
                  onPressed: onLoopToggle!,
                ),
              if (onDownload != null)
                _FloatingRoundIconButton(
                  margin: const EdgeInsets.only(left: 8),
                  icon: Icons.download_rounded,
                  size: _modeIconSize,
                  constraints: _modeButtonConstraints,
                  onPressed: onDownload,
                ),
              if (onClose != null)
                _FloatingRoundIconButton(
                  margin: const EdgeInsets.only(left: 8),
                  icon: Icons.close,
                  size: _modeIconSize,
                  constraints: _modeButtonConstraints,
                  onPressed: onClose,
                ),
            ],
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: onModeToggle != null
              ? _FloatingRoundIconButton(
                  icon: modeToggleIcon,
                  size: _modeIconSize,
                  constraints: _modeButtonConstraints,
                  onPressed: onModeToggle,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class FloatingVideoControlsOverlay extends StatelessWidget {
  const FloatingVideoControlsOverlay({
    super.key,
    required this.title,
    required this.mode,
    required this.isLocked,
    required this.isFullscreen,
    required this.isLooping,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.bufferedPosition,
    required this.modeToggleIcon,
    required this.onTogglePlayPause,
    required this.onSeek,
    required this.onShowControls,
    this.onClose,
    this.onDownload,
    this.onModeToggle,
    this.onLockToggle,
    this.onLoopToggle,
  });

  final String? title;
  final FloatingPlayerMode mode;
  final bool isLocked;
  final bool isFullscreen;
  final bool isLooping;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double bufferedPosition;
  final IconData modeToggleIcon;
  final VoidCallback onTogglePlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onShowControls;
  final VoidCallback? onClose;
  final VoidCallback? onDownload;
  final VoidCallback? onModeToggle;
  final VoidCallback? onLockToggle;
  final VoidCallback? onLoopToggle;

  double get _modeIconSize => mode == FloatingPlayerMode.mini ? 18 : 28;

  BoxConstraints get _modeButtonConstraints => mode == FloatingPlayerMode.mini
      ? const BoxConstraints(minWidth: 32, minHeight: 32)
      : const BoxConstraints(minWidth: 48, minHeight: 48);

  double get _titleFontSize => mode == FloatingPlayerMode.mini ? 12 : 14;

  double get _timeFontSize => mode == FloatingPlayerMode.mini ? 10 : 12;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.6),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.6),
          ],
          stops: const [0.0, 0.2, 0.7, 1.0],
        ),
      ),
      child: Column(
        children: [
          _FloatingVideoTopBar(
            title: title,
            mode: mode,
            isLocked: isLocked,
            isFullscreen: isFullscreen,
            modeIconSize: _modeIconSize,
            modeButtonConstraints: _modeButtonConstraints,
            titleFontSize: _titleFontSize,
            isLooping: isLooping,
            onClose: onClose,
            onDownload: onDownload,
            onLockToggle: onLockToggle,
            onLoopToggle: onLoopToggle,
          ),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: onTogglePlayPause,
                child: Container(
                  width: mode == FloatingPlayerMode.mini ? 52 : 64,
                  height: mode == FloatingPlayerMode.mini ? 52 : 64,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: mode == FloatingPlayerMode.mini ? 28 : 36,
                  ),
                ),
              ),
            ),
          ),
          _FloatingVideoBottomBar(
            modeIconSize: _modeIconSize,
            modeButtonConstraints: _modeButtonConstraints,
            timeFontSize: _timeFontSize,
            position: position,
            duration: duration,
            bufferedPosition: bufferedPosition,
            modeToggleIcon: modeToggleIcon,
            onSeek: onSeek,
            onShowControls: onShowControls,
            onModeToggle: onModeToggle,
          ),
        ],
      ),
    );
  }
}

class FloatingVideoLockOverlay extends StatelessWidget {
  const FloatingVideoLockOverlay({
    super.key,
    required this.visible,
    required this.onWake,
    this.onUnlock,
  });

  final bool visible;
  final VoidCallback onWake;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onWake,
          child: Container(color: Colors.transparent),
        ),
      );
    }

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onWake,
        child: Container(
          color: Colors.transparent,
          child: AnimatedOpacity(
            opacity: 1.0,
            duration: const Duration(milliseconds: 200),
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onUnlock,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(16),
                  child: const Icon(
                    Icons.lock,
                    color: Colors.white70,
                    size: 36,
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

class FloatingVideoGestureHint extends StatelessWidget {
  const FloatingVideoGestureHint({
    super.key,
    required this.gestureHintListenable,
  });

  final ValueListenable<String?> gestureHintListenable;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ValueListenableBuilder<String?>(
          valueListenable: gestureHintListenable,
          builder: (context, gestureHint, child) {
            if (gestureHint == null) return const SizedBox.shrink();
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
    );
  }
}

class _FloatingVideoTopBar extends StatelessWidget {
  const _FloatingVideoTopBar({
    required this.title,
    required this.mode,
    required this.isLocked,
    required this.isFullscreen,
    required this.modeIconSize,
    required this.modeButtonConstraints,
    required this.titleFontSize,
    required this.isLooping,
    this.onClose,
    this.onDownload,
    this.onLockToggle,
    this.onLoopToggle,
  });

  final String? title;
  final FloatingPlayerMode mode;
  final bool isLocked;
  final bool isFullscreen;
  final double modeIconSize;
  final BoxConstraints modeButtonConstraints;
  final double titleFontSize;
  final bool isLooping;
  final VoidCallback? onClose;
  final VoidCallback? onDownload;
  final VoidCallback? onLockToggle;
  final VoidCallback? onLoopToggle;

  @override
  Widget build(BuildContext context) {
    final displayTitle = FloatingVideoPlayer.shortDisplayTitle(title);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          if (displayTitle != null)
            Expanded(
              child: Text(
                displayTitle,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (onLockToggle != null && isFullscreen)
            IconButton(
              icon: Icon(
                isLocked ? Icons.lock : Icons.lock_open,
                color: Colors.white,
                size: modeIconSize,
              ),
              onPressed: onLockToggle,
              padding: EdgeInsets.zero,
              constraints: modeButtonConstraints,
            ),
          if (onLoopToggle != null)
            _FloatingLoopButton(
              isLooping: isLooping,
              compact: mode == FloatingPlayerMode.mini,
              onPressed: onLoopToggle!,
            ),
          if (onDownload != null)
            IconButton(
              icon: Icon(
                Icons.download_rounded,
                color: Colors.white,
                size: modeIconSize,
              ),
              onPressed: onDownload,
              padding: EdgeInsets.zero,
              constraints: modeButtonConstraints,
            ),
          if (onClose != null)
            IconButton(
              icon: Icon(Icons.close, color: Colors.white, size: modeIconSize),
              onPressed: onClose,
              padding: EdgeInsets.zero,
              constraints: modeButtonConstraints,
            ),
        ],
      ),
    );
  }
}

class _FloatingVideoBottomBar extends StatelessWidget {
  const _FloatingVideoBottomBar({
    required this.modeIconSize,
    required this.modeButtonConstraints,
    required this.timeFontSize,
    required this.position,
    required this.duration,
    required this.bufferedPosition,
    required this.modeToggleIcon,
    required this.onSeek,
    required this.onShowControls,
    this.onModeToggle,
  });

  final double modeIconSize;
  final BoxConstraints modeButtonConstraints;
  final double timeFontSize;
  final Duration position;
  final Duration duration;
  final double bufferedPosition;
  final IconData modeToggleIcon;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onShowControls;
  final VoidCallback? onModeToggle;

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (duration > Duration.zero)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: accentColor,
                secondaryActiveTrackColor: Colors.white.withValues(alpha: 0.92),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                thumbColor: accentColor,
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: position.inMilliseconds
                    .clamp(0, duration.inMilliseconds)
                    .toDouble(),
                max: duration.inMilliseconds.toDouble(),
                secondaryTrackValue: bufferedPosition,
                onChanged: (value) {
                  onSeek(Duration(milliseconds: value.toInt()));
                  onShowControls();
                },
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: TextStyle(color: Colors.white, fontSize: timeFontSize),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: timeFontSize,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (onModeToggle != null)
                    IconButton(
                      icon: Icon(
                        modeToggleIcon,
                        color: Colors.white,
                        size: modeIconSize,
                      ),
                      onPressed: onModeToggle,
                      padding: EdgeInsets.zero,
                      constraints: modeButtonConstraints,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _FloatingLoopButton extends StatelessWidget {
  const _FloatingLoopButton({
    required this.isLooping,
    required this.compact,
    required this.onPressed,
    this.margin = EdgeInsets.zero,
  });

  final bool isLooping;
  final bool compact;
  final VoidCallback onPressed;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final label = isLooping ? '循环' : '单次';
    return Container(
      margin: margin,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(
          isLooping ? Icons.repeat_rounded : Icons.repeat_one_rounded,
          size: compact ? 14 : 17,
          color: Colors.white,
        ),
        label: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 10 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: TextButton.styleFrom(
          minimumSize: Size(compact ? 42 : 58, compact ? 30 : 36),
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
          backgroundColor: Colors.black.withValues(alpha: 0.42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class _FloatingRoundIconButton extends StatelessWidget {
  const _FloatingRoundIconButton({
    required this.icon,
    required this.size,
    required this.constraints,
    this.margin = EdgeInsets.zero,
    this.onPressed,
  });

  final IconData icon;
  final double size;
  final BoxConstraints constraints;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: size),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: constraints,
      ),
    );
  }
}
