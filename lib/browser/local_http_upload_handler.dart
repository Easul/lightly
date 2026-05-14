import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef LocalHttpPathResolver = String? Function(String requestPath);
typedef LocalHttpCorsHeaderApplier = void Function(HttpResponse response);
typedef LocalHttpLogger = void Function(String message);

class LocalHttpUploadHandler {
  const LocalHttpUploadHandler();

  Future<void> handleUpload(
    HttpRequest request, {
    required String? uploadKey,
    required String? rootCanonicalPath,
    required LocalHttpPathResolver resolvePath,
    required LocalHttpCorsHeaderApplier addCorsHeaders,
    required LocalHttpLogger logDebug,
  }) async {
    addCorsHeaders(request.response);

    if (_hasUploadKey(uploadKey)) {
      final authHeader = request.headers.value(HttpHeaders.authorizationHeader);
      final uriKey = request.uri.queryParameters['key'];
      final providedKey =
          authHeader?.replaceFirst('Bearer ', '') ?? uriKey ?? '';

      if (!_validateUploadKey(uploadKey, providedKey)) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'error': 'Invalid or missing upload key'}),
        );
        await request.response.close();
        return;
      }
    }

    File? targetFile;
    try {
      final path = request.uri.queryParameters['path'] ?? '/';
      final targetDirPath = resolvePath(path);
      if (targetDirPath == null) {
        request.response.statusCode = HttpStatus.forbidden;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'Invalid upload path'}));
        await request.response.close();
        return;
      }

      final targetDir = Directory(targetDirPath);
      if (!await targetDir.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'error': 'Target directory not found'}),
        );
        await request.response.close();
        return;
      }

      var filename = request.uri.queryParameters['filename'];
      if (filename == null || filename.isEmpty) {
        final disposition = request.headers.value('Content-Disposition');
        if (disposition != null) {
          final reg = RegExp(r'filename="?([^";]+)"?');
          final match = reg.firstMatch(disposition);
          if (match != null) {
            filename = match.group(1);
          }
        }
      }
      filename ??= 'upload_${DateTime.now().millisecondsSinceEpoch}';

      filename = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      if (filename.isEmpty) {
        filename = 'upload_${DateTime.now().millisecondsSinceEpoch}';
      }

      targetFile = await _resolveTargetFile(targetDirPath, filename);

      final sink = targetFile.openWrite();
      var bytesReceived = 0;
      try {
        await for (final chunk in request) {
          bytesReceived += chunk.length;
          if (bytesReceived > 100 * 1024 * 1024) {
            await sink.close();
            if (await targetFile.exists()) {
              await targetFile.delete();
            }
            request.response.statusCode = HttpStatus.requestEntityTooLarge;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({'error': 'File too large (max 100MB)'}),
            );
            await request.response.close();
            return;
          }
          sink.add(chunk);
        }
        await sink.close();
      } catch (_) {
        await sink.close();
        rethrow;
      }

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'success': true,
          'filename': p.basename(targetFile.path),
          'path': request.uri.queryParameters['path'],
          'size': bytesReceived,
          'url': '/${p.relative(targetFile.path, from: rootCanonicalPath)}'
              .replaceAll('\\', '/'),
        }),
      );
      await request.response.close();

      logDebug('Upload successful: ${targetFile.path} ($bytesReceived bytes)');
    } catch (e) {
      logDebug('Upload error: $e');
      if (targetFile != null && await targetFile.exists()) {
        await targetFile.delete();
      }
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'Upload failed: $e'}));
      await request.response.close();
    }
  }

  bool _hasUploadKey(String? uploadKey) =>
      uploadKey != null && uploadKey.isNotEmpty;

  bool _validateUploadKey(String? uploadKey, String? key) {
    if (!_hasUploadKey(uploadKey)) {
      return true;
    }
    return key == uploadKey;
  }

  Future<File> _resolveTargetFile(String targetDirPath, String filename) async {
    var targetFile = File(p.join(targetDirPath, filename));
    if (!await targetFile.exists()) {
      return targetFile;
    }

    final ext = p.extension(filename);
    final base = p.basenameWithoutExtension(filename);
    var counter = 1;
    while (true) {
      final newName = ext.isEmpty ? '${base}_$counter' : '${base}_$counter$ext';
      targetFile = File(p.join(targetDirPath, newName));
      if (!await targetFile.exists()) {
        return targetFile;
      }
      counter++;
    }
  }
}
