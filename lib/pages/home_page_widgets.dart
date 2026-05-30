import 'package:flutter/material.dart';

class HomeAsciiArtCard extends StatelessWidget {
  const HomeAsciiArtCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Semantics(
        label: 'Cute cat ASCII art',
        child: const Text(
          r'''      |
       |       /\_/\
      /        ( o.o )
     /_ _ _ _ _  > ^ <''',
          key: Key('ascii-art'),
          style: TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.0),
          textAlign: TextAlign.center,
          softWrap: false,
        ),
      ),
    );
  }
}
