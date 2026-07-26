class ExpressionEvaluator {
  static double evaluate(String expression) {
    if (expression.isEmpty) {
      throw FormatException('Empty expression');
    }

    final normalized = expression
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll(' ', '');

    return _Evaluator(normalized).evaluate();
  }
}

class _Evaluator {
  final List<String> _tokens;
  int _position = 0;

  _Evaluator._(this._tokens);

  factory _Evaluator(String input) {
    return _Evaluator._(_tokenize(input));
  }

  double evaluate() {
    if (_tokens.isEmpty) {
      throw FormatException('Empty expression');
    }

    final result = _parseExpression();

    if (_position != _tokens.length) {
      throw FormatException('Unexpected token: ${_tokens[_position]}');
    }

    return result;
  }

  double _parseExpression() {
    var left = _parseTerm();
    while (_position < _tokens.length &&
        (_tokens[_position] == '+' || _tokens[_position] == '-')) {
      final op = _tokens[_position];
      _position++;
      final right = _parseTerm();
      if (op == '+') {
        left = left + right;
      } else {
        left = left - right;
      }
    }
    return left;
  }

  double _parseTerm() {
    var left = _parseUnary();
    while (_position < _tokens.length &&
        (_tokens[_position] == '*' || _tokens[_position] == '/')) {
      final op = _tokens[_position];
      _position++;
      final right = _parseUnary();
      if (op == '*') {
        left = left * right;
      } else {
        if (right == 0) {
          throw FormatException('Division by zero');
        }
        left = left / right;
      }
    }
    return left;
  }

  double _parseUnary() {
    if (_position < _tokens.length &&
        (_tokens[_position] == '+' || _tokens[_position] == '-')) {
      final op = _tokens[_position];
      _position++;
      final operand = _parseUnary();
      return op == '+' ? operand : -operand;
    }
    return _parsePrimary();
  }

  double _parsePrimary() {
    if (_position >= _tokens.length) {
      throw FormatException('Unexpected end of expression');
    }

    final token = _tokens[_position];

    if (token == '(') {
      _position++;
      final value = _parseExpression();
      if (_position >= _tokens.length || _tokens[_position] != ')') {
        throw FormatException('Missing closing parenthesis');
      }
      _position++;
      return value;
    }

    if (_isNumber(token)) {
      _position++;
      return double.parse(token);
    }

    throw FormatException('Invalid token: $token');
  }

  static List<String> _tokenize(String input) {
    final tokens = <String>[];
    var i = 0;

    while (i < input.length) {
      final char = input[i];

      if ('+-*/()'.contains(char)) {
        tokens.add(char);
        i++;
      } else if (_isDigitOrDot(char)) {
        final buffer = StringBuffer();
        var hasDot = false;

        while (i < input.length && _isDigitOrDot(input[i])) {
          if (input[i] == '.') {
            if (hasDot) {
              throw FormatException('Multiple dots in number');
            }
            hasDot = true;
          }
          buffer.write(input[i]);
          i++;
        }

        final number = buffer.toString();
        if (number == '.') {
          throw FormatException('Invalid number: .');
        }
        tokens.add(number);
      } else {
        throw FormatException('Invalid character: $char');
      }
    }

    return tokens;
  }

  static bool _isDigitOrDot(String char) {
    return RegExp(r'[0-9.]').hasMatch(char);
  }

  static bool _isNumber(String token) {
    return RegExp(r'^-?[0-9]+\.?[0-9]*$').hasMatch(token) &&
        token != '.' &&
        token != '-';
  }
}
