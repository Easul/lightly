import 'package:flutter/material.dart';

Future<void> showBrowserFavoritesMenuSheet({
  required BuildContext context,
  required VoidCallback onAddFavorite,
  required VoidCallback onToggleReorderMode,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
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
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              _BrowserFavoritesMenuAction(
                label: '添加收藏',
                onTap: () {
                  Navigator.pop(context);
                  onAddFavorite();
                },
              ),
              _BrowserFavoritesMenuAction(
                label: '整理收藏',
                onTap: () {
                  Navigator.pop(context);
                  onToggleReorderMode();
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BrowserFavoritesMenuAction extends StatelessWidget {
  const _BrowserFavoritesMenuAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Theme.of(context).colorScheme.outline,
      ),
      onTap: onTap,
    );
  }
}
