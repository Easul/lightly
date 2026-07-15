class BrowserSuggestion {
  const BrowserSuggestion({
    required this.title,
    required this.url,
    required this.visitCount,
    required this.visitedAt,
  });

  final String title;
  final String url;
  final int visitCount;
  final DateTime visitedAt;
}
