class CalculationHistory {
  final String id;
  final String expression;
  final String result;
  final DateTime createdAt;
  final String note;

  CalculationHistory({
    required this.id,
    required this.expression,
    required this.result,
    required this.createdAt,
    this.note = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'expression': expression,
      'result': result,
      'createdAt': createdAt.toIso8601String(),
      'note': note,
    };
  }

  factory CalculationHistory.fromJson(Map<String, dynamic> json) {
    return CalculationHistory(
      id: json['id'] as String,
      expression: json['expression'] as String,
      result: json['result'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      note: json['note'] as String? ?? '',
    );
  }

  CalculationHistory copyWith({
    String? id,
    String? expression,
    String? result,
    DateTime? createdAt,
    String? note,
  }) {
    return CalculationHistory(
      id: id ?? this.id,
      expression: expression ?? this.expression,
      result: result ?? this.result,
      createdAt: createdAt ?? this.createdAt,
      note: note ?? this.note,
    );
  }
}
