class BrowserFavorite {
  const BrowserFavorite({
    this.id,
    required this.url,
    required this.title,
    required this.createdAt,
    this.sortOrder = 0,
  });

  final int? id;
  final String url;
  final String title;
  final DateTime createdAt;
  final int sortOrder;

  BrowserFavorite copyWith({
    int? id,
    String? url,
    String? title,
    DateTime? createdAt,
    int? sortOrder,
  }) {
    return BrowserFavorite(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'sortOrder': sortOrder,
    };
  }

  factory BrowserFavorite.fromMap(Map<String, Object?> map) {
    return BrowserFavorite(
      id: map['id'] as int?,
      url: map['url'] as String? ?? '',
      title: map['title'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAt'] as num?)?.toInt() ?? 0,
      ),
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}
