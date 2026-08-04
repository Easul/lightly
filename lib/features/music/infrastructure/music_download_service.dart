import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../../core/storage/shared_downloads_access.dart';
import '../../../services/media_scanner_service.dart';
import '../domain/music_track.dart';
import 'music_api_client.dart';

class MusicDownloadService {
  MusicDownloadService({
    required SharedDownloadsAccess downloadsAccess,
    http.Client? client,
  }) : _downloadsAccess = downloadsAccess,
       _client = client ?? http.Client();

  final SharedDownloadsAccess _downloadsAccess;
  final http.Client _client;

  Future<MusicTrack> download(
    MusicTrack track, {
    required bool preferSharedDownloads,
    required bool requestSharedAccessIfNeeded,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final directory = await _downloadsAccess.resolveDirectory(
      preferSharedDownloads: preferSharedDownloads,
      requestSharedAccessIfNeeded: requestSharedAccessIfNeeded,
      androidFallbackFolderName: 'music',
      nonAndroidFallbackFolderName: 'music',
    );
    final request = http.Request('GET', Uri.parse(track.sourceUri));
    request.headers.addAll(<String, String>{
      'User-Agent': MusicApiClient.requestHeaders['User-Agent']!,
      'Accept': 'audio/*, */*;q=0.8',
      'Accept-Encoding': 'identity',
    });
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('下载失败（HTTP ${response.statusCode}）');
    }
    final extension = _extensionFor(track.sourceUri, response.headers);
    // Name files 歌手名-歌曲名 so the MediaStore/display name stays
    // meaningful. Same artist+title from different remote ids or sources
    // must not collapse onto each other: the local library merges downloaded
    // and scanned rows by file name, so a shared file name would cross-link
    // lyrics and artwork of unrelated tracks. A short md5 discriminator is
    // only appended when that collision actually happens; it stays stable
    // per song id / stream URL.
    final baseName = _sanitizeFileName('${track.artist}-${track.title}');
    var output = File(path.join(directory.path, '$baseName$extension'));
    final plainExists = await output.exists();
    final plainSameSong =
        plainExists && await _hasSameFingerprint(output, track);
    if (plainExists && !plainSameSong) {
      // A different song already owns the plain 歌手-歌名 file; fall back to
      // the stable per-id md5 suffix (overwritten in place on re-downloads).
      output = File(
        path.join(
          directory.path,
          '$baseName-${_contentDiscriminator(track)}$extension',
        ),
      );
    }
    final file = await output.open(mode: FileMode.write);
    var receivedBytes = 0;
    final totalBytes = response.contentLength;
    final progressClock = Stopwatch()..start();
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        await file.writeFrom(chunk);
        receivedBytes += chunk.length;
        if (progressClock.elapsedMilliseconds >= 180 ||
            (totalBytes != null && receivedBytes >= totalBytes)) {
          onProgress?.call(receivedBytes, totalBytes);
          progressClock.reset();
        }
      }
      await file.flush();
      onProgress?.call(receivedBytes, totalBytes);
    } catch (_) {
      await file.close();
      if (await output.exists()) await output.delete();
      rethrow;
    }
    await file.close();
    try {
      await _fingerprintFileFor(output).writeAsString(_fingerprintFor(track));
    } on Object {
      // Best-effort marker; a failed write only means a future re-download
      // of the same id may fall back to the md5-suffixed file name.
    }
    await MediaScannerService.scanFile(output.path);
    return track.copyWith(
      // Keep the online search row intact. A downloaded copy needs its own
      // row so the scanned MediaStore entry can inherit its cached metadata.
      trackKey: _downloadedTrackKey(track),
      sourceUri: output.uri.toString(),
      localPath: output.path,
      sourceType: MusicSourceType.downloaded,
    );
  }
}

String _downloadedTrackKey(MusicTrack track) {
  final remoteId = track.remoteId?.trim();
  if (remoteId != null && remoteId.isNotEmpty) {
    return 'downloaded:$remoteId';
  }
  return 'downloaded:${_contentDiscriminator(track)}';
}

String _contentDiscriminator(MusicTrack track) {
  final remoteId = track.remoteId?.trim();
  final seed = remoteId != null && remoteId.isNotEmpty
      ? 'id:$remoteId'
      : track.sourceUri;
  return md5.convert(utf8.encode(seed)).toString().substring(0, 6);
}

/// Fingerprint marker written next to a downloaded file so a re-download of
/// the same song id/stream can overwrite the plain 歌手-歌名 file instead of
/// spawning an md5-suffixed copy of itself.
String _fingerprintFor(MusicTrack track) {
  final remoteId = track.remoteId?.trim();
  return remoteId != null && remoteId.isNotEmpty
      ? 'id:$remoteId'
      : 'uri:${track.sourceUri}';
}

File _fingerprintFileFor(File audio) => File(audio.path + _fingerprintSuffix);

const String _fingerprintSuffix = '.lightly.meta';

Future<bool> _hasSameFingerprint(File audio, MusicTrack track) async {
  final marker = _fingerprintFileFor(audio);
  if (!await marker.exists()) return false;
  try {
    return (await marker.readAsString()).trim() == _fingerprintFor(track);
  } on Object {
    return false;
  }
}

String _sanitizeFileName(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.isEmpty ? 'music' : cleaned;
}

String _extensionFor(String url, Map<String, String> headers) {
  final uriExtension = path
      .extension(Uri.tryParse(url)?.path ?? '')
      .toLowerCase();
  if (<String>{
    '.mp3',
    '.m4a',
    '.aac',
    '.flac',
    '.wav',
    '.ogg',
    '.opus',
  }.contains(uriExtension)) {
    return uriExtension;
  }
  final contentType = headers['content-type']?.toLowerCase() ?? '';
  if (contentType.contains('flac')) return '.flac';
  if (contentType.contains('mp4') || contentType.contains('m4a')) return '.m4a';
  if (contentType.contains('ogg')) return '.ogg';
  if (contentType.contains('wav')) return '.wav';
  if (contentType.contains('aac')) return '.aac';
  return '.mp3';
}
