import 'package:flutter/material.dart';

enum LongPressActionType { link, image }

class BrowserLongPressActionsSheet extends StatelessWidget {
  const BrowserLongPressActionsSheet({
    super.key,
    required this.type,
    required this.url,
    required this.onOpenInNewTab,
    required this.onCopyLink,
    required this.onDownload,
  });

  final LongPressActionType type;
  final String url;
  final VoidCallback onOpenInNewTab;
  final VoidCallback onCopyLink;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              // URL preview
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ActionItem(
                icon: Icons.open_in_new_rounded,
                label: type == LongPressActionType.image
                    ? '新标签页打开图片'
                    : '新标签页打开',
                onTap: () {
                  Navigator.pop(context);
                  onOpenInNewTab();
                },
              ),
              _ActionItem(
                icon: Icons.copy_rounded,
                label: type == LongPressActionType.image ? '复制图片链接' : '复制链接',
                onTap: () {
                  Navigator.pop(context);
                  onCopyLink();
                },
              ),
              _ActionItem(
                icon: Icons.download_rounded,
                label: type == LongPressActionType.image ? '下载图片' : '下载链接',
                onTap: () {
                  Navigator.pop(context);
                  onDownload();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BrowserYouTubeLongPressActionsSheet extends StatelessWidget {
  const BrowserYouTubeLongPressActionsSheet({
    super.key,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.originalVideoUrl,
    required this.onOpenVideo,
    required this.onCopyVideo,
    required this.onOpenThumbnail,
    required this.onCopyThumbnail,
    required this.onOpenOriginalVideo,
  });

  final String videoUrl;
  final String thumbnailUrl;
  final String originalVideoUrl;
  final VoidCallback onOpenVideo;
  final VoidCallback onCopyVideo;
  final VoidCallback onOpenThumbnail;
  final VoidCallback onCopyThumbnail;
  final VoidCallback onOpenOriginalVideo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  videoUrl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ActionItem(
                icon: Icons.open_in_new_rounded,
                label: '新页面打开视频链接',
                onTap: () {
                  Navigator.pop(context);
                  onOpenVideo();
                },
              ),
              _ActionItem(
                icon: Icons.copy_rounded,
                label: '复制视频链接',
                onTap: () {
                  Navigator.pop(context);
                  onCopyVideo();
                },
              ),
              _ActionItem(
                icon: Icons.image_search_rounded,
                label: '新页面打开封面图',
                onTap: () {
                  Navigator.pop(context);
                  onOpenThumbnail();
                },
              ),
              _ActionItem(
                icon: Icons.link_rounded,
                label: '复制封面图链接',
                onTap: () {
                  Navigator.pop(context);
                  onCopyThumbnail();
                },
              ),
              _ActionItem(
                icon: Icons.ondemand_video_rounded,
                label: '新页面打开原始视频链接',
                onTap: () {
                  Navigator.pop(context);
                  onOpenOriginalVideo();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(icon, color: colorScheme.onSurfaceVariant),
      title: Text(label),
      onTap: onTap,
    );
  }
}
