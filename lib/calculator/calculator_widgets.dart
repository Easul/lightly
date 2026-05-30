import 'package:flutter/material.dart';

class CalculatorResultCard extends StatelessWidget {
  const CalculatorResultCard({
    super.key,
    required this.result,
    required this.fontSize,
  });

  final String result;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '结果:',
            style: TextStyle(fontSize: 14, color: colorScheme.primary),
          ),
          const SizedBox(height: 4),
          Text(
            result,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class CalculatorErrorCard extends StatelessWidget {
  const CalculatorErrorCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('错误:', style: TextStyle(fontSize: 14, color: colorScheme.error)),
          const SizedBox(height: 4),
          Text(
            message,
            style: TextStyle(fontSize: 16, color: colorScheme.onErrorContainer),
          ),
        ],
      ),
    );
  }
}

class CalculatorKeypad extends StatelessWidget {
  const CalculatorKeypad({
    super.key,
    required this.onNumberPressed,
    required this.onOperatorPressed,
    required this.onDeletePressed,
    required this.onCalculatePressed,
    required this.buttonFontSize,
    required this.buttonPadding,
  });

  final ValueChanged<String> onNumberPressed;
  final ValueChanged<String> onOperatorPressed;
  final VoidCallback onDeletePressed;
  final VoidCallback onCalculatePressed;
  final double buttonFontSize;
  final double buttonPadding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Row(
          children: [
            _CalculatorButton(
              '7',
              onPressed: onNumberPressed,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
            _CalculatorButton(
              '8',
              onPressed: onNumberPressed,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
            _CalculatorButton(
              '9',
              onPressed: onNumberPressed,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
            _CalculatorButton(
              '÷',
              onPressed: (_) => onOperatorPressed('/'),
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
          ],
        ),
        Row(
          children: [
            _CalculatorButton(
              '4',
              onPressed: onNumberPressed,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
            _CalculatorButton(
              '5',
              onPressed: onNumberPressed,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
            _CalculatorButton(
              '6',
              onPressed: onNumberPressed,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
            _CalculatorButton(
              '×',
              onPressed: (_) => onOperatorPressed('*'),
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
          ],
        ),
        Row(
          children: [
            _CalculatorButton(
              '1',
              onPressed: onNumberPressed,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
            _CalculatorButton(
              '2',
              onPressed: onNumberPressed,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
            _CalculatorButton(
              '3',
              onPressed: onNumberPressed,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
            _CalculatorButton(
              '-',
              onPressed: onOperatorPressed,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
          ],
        ),
        Row(
          children: [
            _CalculatorButton(
              '0',
              onPressed: onNumberPressed,
              flex: 2,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
            _CalculatorButton(
              '.',
              onPressed: onOperatorPressed,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
            _CalculatorButton(
              '+',
              onPressed: onOperatorPressed,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
          ],
        ),
        Row(
          children: [
            _CalculatorButton(
              '(',
              onPressed: onOperatorPressed,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
            _CalculatorButton(
              ')',
              onPressed: onOperatorPressed,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
            _CalculatorButton(
              '⌫',
              onPressed: (_) => onDeletePressed(),
              backgroundColor: colorScheme.secondaryContainer,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
            _CalculatorButton(
              '=',
              onPressed: (_) => onCalculatePressed(),
              backgroundColor: colorScheme.primary,
              textColor: colorScheme.onPrimary,
              fontSize: buttonFontSize,
              verticalPadding: buttonPadding,
            ),
          ],
        ),
      ],
    );
  }
}

class _CalculatorButton extends StatelessWidget {
  const _CalculatorButton(
    this.text, {
    required this.onPressed,
    this.backgroundColor,
    this.textColor,
    this.flex = 1,
    this.fontSize = 24,
    this.verticalPadding = 18,
  });

  final String text;
  final ValueChanged<String> onPressed;
  final Color? backgroundColor;
  final Color? textColor;
  final int flex;
  final double fontSize;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: ElevatedButton(
          onPressed: () => onPressed(text),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                backgroundColor ?? colorScheme.surfaceContainerHighest,
            foregroundColor: textColor ?? colorScheme.onSurface,
            padding: EdgeInsets.symmetric(vertical: verticalPadding),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
