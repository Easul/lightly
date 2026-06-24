import 'package:flutter/material.dart';

class NativeVideoDialogHeader extends StatelessWidget {
  const NativeVideoDialogHeader({
    super.key,
    this.title,
    this.loopingEnabled = false,
    this.onToggleLooping,
  });

  final String? title;
  final bool loopingEnabled;
  final VoidCallback? onToggleLooping;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Expanded(child: _NativeVideoDialogTitle(title: title)),
          if (onToggleLooping != null)
            TextButton.icon(
              onPressed: onToggleLooping,
              icon: Icon(
                loopingEnabled ? Icons.repeat : Icons.looks_one_outlined,
              ),
              label: Text(loopingEnabled ? '循环' : '单次'),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _NativeVideoDialogTitle extends StatelessWidget {
  const _NativeVideoDialogTitle({required this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    final resolvedTitle = title?.trim();
    return Text(
      resolvedTitle?.isNotEmpty == true ? resolvedTitle! : '视频播放',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleSmall,
    );
  }
}

class NativeVideoLoadingView extends StatelessWidget {
  const NativeVideoLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator(color: Colors.white));
  }
}

class NativeVideoErrorView extends StatelessWidget {
  const NativeVideoErrorView({super.key, required this.message, this.onClose});

  final String message;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              message,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Material(
            color: Colors.black.withValues(alpha: 0.45),
            shape: const CircleBorder(),
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: '关闭',
              onPressed: onClose ?? Navigator.of(context).maybePop,
            ),
          ),
        ),
      ],
    );
  }
}
