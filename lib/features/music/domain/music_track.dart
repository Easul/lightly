enum MusicSourceType { online, local, downloaded }

class MusicTrack {
  const MusicTrack({
    required this.trackKey,
    required this.title,
    required this.artist,
    required this.album,
    required this.sourceUri,
    required this.sourceType,
    this.remoteId,
    this.artworkUrl,
    this.localPath,
    this.durationMs = 0,
    this.lyric,
    this.translatedLyric,
    this.isFavorite = false,
    this.groupName = '',
    this.updatedAt,
    this.lastPlayedAt,
  });

  final String trackKey;
  final String? remoteId;
  final String title;
  final String artist;
  final String album;
  final String? artworkUrl;
  final String sourceUri;
  final String? localPath;
  final MusicSourceType sourceType;
  final int durationMs;
  final String? lyric;
  final String? translatedLyric;
  final bool isFavorite;
  final String groupName;
  final DateTime? updatedAt;
  final DateTime? lastPlayedAt;

  bool get isRemote => remoteId != null && remoteId!.isNotEmpty;
  bool get isPlayable => sourceUri.trim().isNotEmpty || isRemote;

  factory MusicTrack.fromSearchJson(Map<String, dynamic> json) {
    final remoteId = '${json['id'] ?? ''}'.trim();
    return MusicTrack(
      trackKey: 'online:$remoteId',
      remoteId: remoteId,
      title: '${json['name'] ?? '未知歌曲'}',
      artist: '${json['artists'] ?? json['artist'] ?? '未知歌手'}',
      album: '${json['album'] ?? '未知专辑'}',
      artworkUrl: _nullableString(json['picUrl']),
      sourceUri: _nullableString(json['url']) ?? '',
      sourceType: MusicSourceType.online,
    );
  }

  factory MusicTrack.fromPlatformMap(Map<Object?, Object?> map) {
    final uri = '${map['uri'] ?? ''}'.trim();
    final path = _nullableString(map['path']);
    final keySeed = uri.isNotEmpty ? uri : path ?? '${map['id'] ?? ''}';
    return MusicTrack(
      trackKey: 'local:$keySeed',
      title: '${map['title'] ?? map['displayName'] ?? '未知歌曲'}',
      artist: '${map['artist'] ?? '未知歌手'}',
      album: '${map['album'] ?? '未知专辑'}',
      artworkUrl: _nullableString(map['artworkUri']),
      sourceUri: uri.isNotEmpty
          ? uri
          : (path == null ? '' : Uri.file(path).toString()),
      localPath: path,
      sourceType: MusicSourceType.local,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
    );
  }

  factory MusicTrack.fromDatabaseMap(Map<String, Object?> map) {
    return MusicTrack(
      trackKey: map['trackKey'] as String,
      remoteId: map['remoteId'] as String?,
      title: map['title'] as String,
      artist: map['artist'] as String,
      album: map['album'] as String,
      artworkUrl: map['artworkUrl'] as String?,
      sourceUri: map['sourceUri'] as String,
      localPath: map['localPath'] as String?,
      sourceType: MusicSourceType.values.byName(map['sourceType'] as String),
      durationMs: map['durationMs'] as int,
      lyric: map['lyric'] as String?,
      translatedLyric: map['translatedLyric'] as String?,
      isFavorite: (map['isFavorite'] as int) == 1,
      groupName: map['groupName'] as String,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int),
      lastPlayedAt: map['lastPlayedAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['lastPlayedAt'] as int),
    );
  }

  Map<String, Object?> toDatabaseMap() {
    return <String, Object?>{
      'trackKey': trackKey,
      'remoteId': remoteId,
      'title': title,
      'artist': artist,
      'album': album,
      'artworkUrl': artworkUrl,
      'sourceUri': sourceUri,
      'localPath': localPath,
      'sourceType': sourceType.name,
      'durationMs': durationMs,
      'lyric': lyric,
      'translatedLyric': translatedLyric,
      'isFavorite': isFavorite ? 1 : 0,
      'groupName': groupName,
      'updatedAt': (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      'lastPlayedAt': lastPlayedAt?.millisecondsSinceEpoch,
    };
  }

  MusicTrack copyWith({
    String? title,
    String? artist,
    String? album,
    String? artworkUrl,
    String? sourceUri,
    String? localPath,
    MusicSourceType? sourceType,
    int? durationMs,
    String? lyric,
    String? translatedLyric,
    bool? isFavorite,
    String? groupName,
    DateTime? updatedAt,
    DateTime? lastPlayedAt,
  }) {
    return MusicTrack(
      trackKey: trackKey,
      remoteId: remoteId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      sourceUri: sourceUri ?? this.sourceUri,
      localPath: localPath ?? this.localPath,
      sourceType: sourceType ?? this.sourceType,
      durationMs: durationMs ?? this.durationMs,
      lyric: lyric ?? this.lyric,
      translatedLyric: translatedLyric ?? this.translatedLyric,
      isFavorite: isFavorite ?? this.isFavorite,
      groupName: groupName ?? this.groupName,
      updatedAt: updatedAt ?? this.updatedAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}
