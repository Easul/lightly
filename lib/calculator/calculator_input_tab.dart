import 'package:flutter/material.dart';

import 'calculator_widgets.dart';

class CalculatorInputTab extends StatelessWidget {
  const CalculatorInputTab({
    super.key,
    required this.expressionController,
    required this.expressionFocusNode,
    required this.result,
    required this.errorMessage,
    required this.onClearPressed,
    required this.onCalculatePressed,
    required this.onNumberPressed,
    required this.onOperatorPressed,
    required this.onDeletePressed,
    required this.contextMenuBuilder,
  });

  final TextEditingController expressionController;
  final FocusNode expressionFocusNode;
  final String result;
  final String errorMessage;
  final VoidCallback onClearPressed;
  final VoidCallback onCalculatePressed;
  final ValueChanged<String> onNumberPressed;
  final ValueChanged<String> onOperatorPressed;
  final VoidCallback onDeletePressed;
  final EditableTextContextMenuBuilder contextMenuBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactLayout = constraints.maxHeight < 640;
        final resultFontSize = compactLayout ? 28.0 : 32.0;
        final buttonFontSize = compactLayout ? 20.0 : 24.0;
        final buttonPadding = compactLayout ? 14.0 : 18.0;
        final blockSpacing = compactLayout ? 12.0 : 16.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _ExpressionField(
                controller: expressionController,
                focusNode: expressionFocusNode,
                onClearPressed: onClearPressed,
                onCalculatePressed: onCalculatePressed,
                contextMenuBuilder: contextMenuBuilder,
              ),
              SizedBox(height: blockSpacing),
              if (result.isNotEmpty)
                CalculatorResultCard(result: result, fontSize: resultFontSize),
              if (result.isNotEmpty) SizedBox(height: blockSpacing),
              if (errorMessage.isNotEmpty)
                CalculatorErrorCard(message: errorMessage),
              if (errorMessage.isNotEmpty) SizedBox(height: blockSpacing),
              CalculatorKeypad(
                onNumberPressed: onNumberPressed,
                onOperatorPressed: onOperatorPressed,
                onDeletePressed: onDeletePressed,
                onCalculatePressed: onCalculatePressed,
                buttonFontSize: buttonFontSize,
                buttonPadding: buttonPadding,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExpressionField extends StatelessWidget {
  const _ExpressionField({
    required this.controller,
    required this.focusNode,
    required this.onClearPressed,
    required this.onCalculatePressed,
    required this.contextMenuBuilder,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClearPressed;
  final VoidCallback onCalculatePressed;
  final EditableTextContextMenuBuilder contextMenuBuilder;

  @override
  Widget build(BuildContext context) {
    return TextField(
      focusNode: focusNode,
      controller: controller,
      decoration: InputDecoration(
        labelText: '表达式',
        hintText: '例如: 1+2*3 或 (4+5)*6',
        prefixIcon: const Icon(Icons.edit),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: IconButton(
          icon: const Icon(Icons.clear),
          onPressed: onClearPressed,
        ),
      ),
      style: const TextStyle(fontSize: 20),
      onSubmitted: (_) => onCalculatePressed(),
      contextMenuBuilder: contextMenuBuilder,
    );
  }
}
