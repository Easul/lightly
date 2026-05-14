import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/calculator/expression_evaluator.dart';

void main() {
  group('ExpressionEvaluator', () {
    test('supports full-width parentheses by normalizing them to ASCII', () {
      expect(ExpressionEvaluator.evaluate('（1+2）×3'), 9);
    });
  });
}
