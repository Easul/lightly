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
                icon: Icons.add,
                label: '添加收藏',
                onTap: () {
                  Navigator.pop(context);
                  onAddFavorite();
                },
              ),
              _BrowserFavoritesMenuAction(
                icon: Icons.drag_indicator_rounded,
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
  const _BrowserFavoritesMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(leading: Icon(icon), title: Text(label), onTap: onTap);
  }
}
