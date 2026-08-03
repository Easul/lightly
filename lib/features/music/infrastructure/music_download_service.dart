import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../../core/storage/shared_downloads_access.dart';
import '../../../services/media_scanner_service.dart';
import '../domain/music_track.dart';

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
  }) async {
    final directory = await _downloadsAccess.resolveDirectory(
      preferSharedDownloads: preferSharedDownloads,
      requestSharedAccessIfNeeded: requestSharedAccessIfNeeded,
      androidFallbackFolderName: 'music',
      nonAndroidFallbackFolderName: 'music',
    );
    final request = http.Request('GET', Uri.parse(track.sourceUri));
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('下载失败（HTTP ${response.statusCode}）');
    }
    final extension = _extensionFor(track.sourceUri, response.headers);
    final baseName = _sanitizeFileName('${track.artist} - ${track.title}');
    final output = await _uniqueFile(directory, '$baseName$extension');
    final sink = output.openWrite();
    try {
      await response.stream.timeout(const Duration(seconds: 30)).pipe(sink);
    } catch (_) {
      await sink.close();
      if (await output.exists()) await output.delete();
      rethrow;
    }
    await MediaScannerService.scanFile(output.path);
    return track.copyWith(
      sourceUri: output.uri.toString(),
      localPath: output.path,
      sourceType: MusicSourceType.downloaded,
    );
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

Future<File> _uniqueFile(Directory directory, String name) async {
  var candidate = File(path.join(directory.path, name));
  var suffix = 2;
  final extension = path.extension(name);
  final stem = path.basenameWithoutExtension(name);
  while (await candidate.exists()) {
    candidate = File(path.join(directory.path, '$stem ($suffix)$extension'));
    suffix++;
  }
  return candidate;
}
