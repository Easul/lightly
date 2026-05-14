import 'dart:io';

import 'package:path/path.dart' as p;

class LocalHttpFileHandler {
  const LocalHttpFileHandler();

  Future<bool> tryServeSpaFallback(
    HttpRequest request, {
    required String? rootCanonicalPath,
    required Future<void> Function(HttpRequest request, File file) serveFile,
  }) async {
    final canonicalRoot = rootCanonicalPath;
    if (canonicalRoot == null) {
      return false;
    }

    final acceptHeader =
        request.headers.value(HttpHeaders.acceptHeader)?.toLowerCase() ?? '';
    final requestPath = request.uri.path;
    final likelyHtmlNavigation =
        acceptHeader.contains('text/html') ||
        !p.basename(requestPath).contains('.');
    if (!likelyHtmlNavigation) {
      return false;
    }

    final indexFile = File(p.join(canonicalRoot, 'index.html'));
    if (!await indexFile.exists()) {
      return false;
    }

    await serveFile(request, indexFile);
    return true;
  }

  Future<void> serveFile(HttpRequest request, File file) async {
    final readableHandle = await file.open(mode: FileMode.read);
    await readableHandle.close();

    final stat = await file.stat();
    request.response.headers.contentType = lookupContentType(file.path);
    request.response.contentLength = stat.size;
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  ContentType lookupContentType(String filePath) {
    switch (p.extension(filePath).toLowerCase()) {
      case '.html':
      case '.htm':
        return ContentType.html;
      case '.css':
        return ContentType('text', 'css', charset: 'utf-8');
      case '.js':
        return ContentType('application', 'javascript', charset: 'utf-8');
      case '.json':
        return ContentType.json;
      case '.md':
      case '.markdown':
        return ContentType('text', 'markdown', charset: 'utf-8');
      case '.txt':
      case '.log':
        return ContentType.text;
      case '.svg':
        return ContentType('image', 'svg+xml');
      case '.png':
        return ContentType('image', 'png');
      case '.jpg':
      case '.jpeg':
        return ContentType('image', 'jpeg');
      case '.gif':
        return ContentType('image', 'gif');
      case '.webp':
        return ContentType('image', 'webp');
      case '.mp4':
        return ContentType('video', 'mp4');
      case '.mp3':
        return ContentType('audio', 'mpeg');
      case '.pdf':
        return ContentType('application', 'pdf');
      default:
        return ContentType.binary;
    }
  }
}
