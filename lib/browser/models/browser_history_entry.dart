class BrowserHistoryEntry {
  const BrowserHistoryEntry({
    this.id,
    required this.url,
    required this.title,
    required this.visitedAt,
    required this.visitCount,
  });

  final int? id;
  final String url;
  final String title;
  final DateTime visitedAt;
  final int visitCount;

  BrowserHistoryEntry copyWith({
    int? id,
    String? url,
    String? title,
    DateTime? visitedAt,
    int? visitCount,
  }) {
    return BrowserHistoryEntry(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      visitedAt: visitedAt ?? this.visitedAt,
      visitCount: visitCount ?? this.visitCount,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'visitedAt': visitedAt.millisecondsSinceEpoch,
      'visitCount': visitCount,
    };
  }

  factory BrowserHistoryEntry.fromMap(Map<String, Object?> map) {
    return BrowserHistoryEntry(
      id: map['id'] as int?,
      url: map['url'] as String? ?? '',
      title: map['title'] as String? ?? '',
      visitedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['visitedAt'] as num?)?.toInt() ?? 0,
      ),
      visitCount: (map['visitCount'] as num?)?.toInt() ?? 0,
    );
  }
}
