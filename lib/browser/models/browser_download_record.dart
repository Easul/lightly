class BrowserDownloadRecord {
  const BrowserDownloadRecord({
    this.id,
    required this.url,
    required this.fileName,
    required this.status,
    required this.savedPath,
    required this.totalBytes,
    required this.bytesReceived,
    required this.createdAt,
  });

  final int? id;
  final String url;
  final String fileName;
  final String status;
  final String? savedPath;
  final int totalBytes;
  final int bytesReceived;
  final DateTime createdAt;

  BrowserDownloadRecord copyWith({
    int? id,
    String? url,
    String? fileName,
    String? status,
    String? savedPath,
    bool clearSavedPath = false,
    int? totalBytes,
    int? bytesReceived,
    DateTime? createdAt,
  }) {
    return BrowserDownloadRecord(
      id: id ?? this.id,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      status: status ?? this.status,
      savedPath: clearSavedPath ? null : savedPath ?? this.savedPath,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'url': url,
      'fileName': fileName,
      'status': status,
      'savedPath': savedPath,
      'totalBytes': totalBytes,
      'bytesReceived': bytesReceived,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory BrowserDownloadRecord.fromMap(Map<String, Object?> map) {
    return BrowserDownloadRecord(
      id: map['id'] as int?,
      url: map['url'] as String? ?? '',
      fileName: map['fileName'] as String? ?? '',
      status: map['status'] as String? ?? '',
      savedPath: map['savedPath'] as String?,
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      bytesReceived: (map['bytesReceived'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
