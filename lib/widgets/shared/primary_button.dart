import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
  });

  const PrimaryButton.outlined({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  }) : outlined = true;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: icon == null
          ? Text(label, key: ValueKey<String>(label))
          : Row(
              key: ValueKey<String>(
                '${outlined ? 'outlined' : 'filled'}-$label',
              ),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Text(label),
              ],
            ),
    );

    if (outlined) {
      return OutlinedButton(onPressed: onPressed, child: child);
    }
    return FilledButton(onPressed: onPressed, child: child);
  }
}
