import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/music_track.dart';

class MusicSearchPage {
  const MusicSearchPage({required this.tracks, required this.total});

  final List<MusicTrack> tracks;
  final int total;
}

class MusicLyrics {
  const MusicLyrics({this.original, this.translated});

  final String? original;
  final String? translated;
}

class MusicApiClient {
  MusicApiClient({http.Client? client}) : _client = client ?? http.Client();

  static const int searchLimit = 10;

  final http.Client _client;

  Future<MusicSearchPage> search({
    required String apiBaseUrl,
    required String keyword,
    required int page,
    required String apiKey,
  }) async {
    final json = await _getJson(apiBaseUrl, '163_search', <String, String>{
      'keyword': keyword.trim(),
      'limit': '$searchLimit',
      'offset': '${(page - 1) * searchLimit}',
      'apikey': apiKey,
    });
    final data = json['data'];
    final tracks = data is List
        ? data
              .whereType<Map>()
              .map(
                (item) =>
                    MusicTrack.fromSearchJson(item.cast<String, dynamic>()),
              )
              .toList(growable: false)
        : const <MusicTrack>[];
    return MusicSearchPage(
      tracks: tracks,
      total: (json['total'] as num?)?.toInt() ?? tracks.length,
    );
  }

  Future<MusicTrack> resolve({
    required String apiBaseUrl,
    required MusicTrack track,
    required String apiKey,
    String level = 'standard',
  }) async {
    final json = await _getJson(apiBaseUrl, '163_music', <String, String>{
      'id': track.remoteId!,
      'level': level,
      'apikey': apiKey,
    });
    final data = json['data'];
    if (data is! Map) throw const FormatException('音乐解析结果缺少 data');
    final resolved = data.cast<String, dynamic>();
    final sourceUri = '${resolved['url'] ?? ''}'.trim();
    if (sourceUri.isEmpty) throw const FormatException('音乐解析结果缺少播放地址');
    return track.copyWith(
      title: '${resolved['name'] ?? track.title}',
      artist: '${resolved['artist'] ?? track.artist}',
      album: '${resolved['album'] ?? track.album}',
      artworkUrl: resolved['picUrl']?.toString(),
      sourceUri: sourceUri,
    );
  }

  Future<MusicLyrics> lyrics({
    required String apiBaseUrl,
    required String remoteId,
    required String apiKey,
  }) async {
    final json = await _getJson(apiBaseUrl, '163_lyric', <String, String>{
      'id': remoteId,
      'apikey': apiKey,
    });
    final data = json['data'];
    if (data is! Map) return const MusicLyrics();
    return MusicLyrics(
      original: _stringOrNull(data['lrc']),
      translated: _stringOrNull(data['tlyric']),
    );
  }

  Future<Map<String, dynamic>> _getJson(
    String apiBaseUrl,
    String endpoint,
    Map<String, String> query,
  ) async {
    final uri = _parseBaseUri(
      apiBaseUrl,
    ).resolve(endpoint).replace(queryParameters: query);
    final response = await _client
        .get(
          uri,
          headers: const <String, String>{
            'User-Agent': 'Mozilla/5.0 Lightly Music Player',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      final serverMessage = _responseMessage(response.body);
      final suffix = serverMessage == null ? '' : '：$serverMessage';
      throw MusicApiException('请求失败（HTTP ${response.statusCode}）$suffix');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('音乐接口返回格式无效');
    }
    if ((decoded['code'] as num?)?.toInt() != 200) {
      throw MusicApiException('${decoded['msg'] ?? '音乐接口请求失败'}');
    }
    return decoded;
  }
}

String? _responseMessage(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final message = decoded['msg']?.toString().trim();
    if (message == null || message.isEmpty) return null;
    final normalized = message.replaceAll(RegExp(r'[\r\n]+'), ' ');
    return normalized.length <= 160 ? normalized : normalized.substring(0, 160);
  } on Object {
    return null;
  }
}

Uri _parseBaseUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    throw const FormatException('音乐 API 地址必须是有效的 HTTP(S) 地址');
  }
  final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
  return uri.replace(path: path);
}

class MusicApiException implements Exception {
  const MusicApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

String? _stringOrNull(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
