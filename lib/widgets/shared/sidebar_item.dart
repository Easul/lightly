import 'package:flutter/material.dart';

class SidebarItem extends StatelessWidget {
  const SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.72)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: ListTile(
          onTap: onTap,
          leading: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.14)
                  : colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              size: 20,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          title: Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
          trailing: Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: colorScheme.outline,
          ),
        ),
      ),
    );
  }
}
