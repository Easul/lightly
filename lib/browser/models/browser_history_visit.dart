class BrowserHistoryVisit {
  const BrowserHistoryVisit({
    this.id,
    required this.url,
    required this.title,
    required this.visitedAt,
  });

  final int? id;
  final String url;
  final String title;
  final DateTime visitedAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'visitedAt': visitedAt.millisecondsSinceEpoch,
    };
  }

  factory BrowserHistoryVisit.fromMap(Map<String, Object?> map) {
    return BrowserHistoryVisit(
      id: map['id'] as int?,
      url: map['url'] as String? ?? '',
      title: map['title'] as String? ?? '',
      visitedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['visitedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
