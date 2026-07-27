import 'dart:io';

class BrowserDownloadFileNameResolver {
  BrowserDownloadFileNameResolver({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  String resolve({
    String? suggestedFileName,
    String? contentDisposition,
    required Uri url,
    String? mimeType,
  }) {
    final disposition = fileNameFromContentDisposition(contentDisposition);
    if (disposition != null) {
      return disposition;
    }
    final query = _fileNameFromQuery(url);
    if (query != null) {
      return _withMimeExtension(query, mimeType);
    }
    final suggested = _normalizeCandidate(suggestedFileName);
    if (suggested != null) {
      return _withMimeExtension(suggested, mimeType, replaceBinary: true);
    }
    final path = _fileNameFromPath(url);
    if (path != null) {
      return _withMimeExtension(path, mimeType);
    }
    return _withMimeExtension(
      _defaultFileName(),
      mimeType,
      replaceBinary: true,
    );
  }

  String? resolveFromResponse({
    required String currentFileName,
    required Uri requestUrl,
    required HttpClientResponse response,
  }) {
    final disposition = fileNameFromContentDisposition(
      response.headers.value('content-disposition'),
    );
    if (disposition != null) {
      return disposition;
    }

    final finalUrl = resolveFinalUrl(requestUrl, response.redirects);
    final query = _fileNameFromQuery(finalUrl);
    if (query != null) {
      return _withMimeExtension(query, response.headers.contentType?.mimeType);
    }

    if (!_isGenericFileName(currentFileName)) {
      return null;
    }
    final path = _fileNameFromPath(finalUrl);
    if (path != null) {
      return _withMimeExtension(
        path,
        response.headers.contentType?.mimeType,
        replaceBinary: true,
      );
    }
    return _withMimeExtension(
      sanitize(currentFileName),
      response.headers.contentType?.mimeType,
      replaceBinary: true,
    );
  }

  Uri resolveFinalUrl(Uri requestUrl, List<RedirectInfo> redirects) {
    var resolved = requestUrl;
    for (final redirect in redirects) {
      resolved = resolved.resolveUri(redirect.location);
    }
    return resolved;
  }

  String? fileNameFromContentDisposition(String? value) {
    final header = value?.trim();
    if (header == null || header.isEmpty) {
      return null;
    }

    final extendedMatch = RegExp(
      r'''(?:^|;)\s*filename\*\s*=\s*(?:"([^"]*)"|([^;]*))''',
      caseSensitive: false,
    ).firstMatch(header);
    final extendedValue =
        extendedMatch?.group(1)?.trim() ?? extendedMatch?.group(2)?.trim();
    final normalizedExtended = _normalizeCandidate(
      _decodeExtendedValue(extendedValue),
    );
    if (normalizedExtended != null) {
      return normalizedExtended;
    }

    final quotedMatch = RegExp(
      r'''(?:^|;)\s*filename\s*=\s*"((?:\\.|[^"])*)"''',
      caseSensitive: false,
    ).firstMatch(header);
    final quoted = quotedMatch
        ?.group(1)
        ?.replaceAll(r'\"', '"')
        .replaceAll(r'\\', '\\');
    final normalizedQuoted = _normalizeCandidate(quoted);
    if (normalizedQuoted != null) {
      return normalizedQuoted;
    }

    final plainMatch = RegExp(
      r'''(?:^|;)\s*filename\s*=\s*([^;]+)''',
      caseSensitive: false,
    ).firstMatch(header);
    return _normalizeCandidate(plainMatch?.group(1));
  }

  String sanitize(String name) {
    final sanitized = name
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'[\x00-\x1f\x7f\\/:*?"<>|]'), '_')
        .trim();
    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
      return _defaultFileName();
    }
    return sanitized;
  }

  String? _fileNameFromQuery(Uri uri) {
    const preferredKeys = <String>{
      'filename',
      'file_name',
      'file-name',
      'downloadfilename',
      'download_filename',
      'download',
      'name',
      'file',
    };
    for (final entry in uri.queryParametersAll.entries) {
      final key = entry.key.toLowerCase();
      if (key == 'response-content-disposition' ||
          key == 'content-disposition') {
        for (final value in entry.value) {
          final result = fileNameFromContentDisposition(value);
          if (result != null) {
            return result;
          }
        }
      }
      if (!preferredKeys.contains(key)) {
        continue;
      }
      final requireExtension = const <String>{
        'download',
        'name',
        'file',
      }.contains(key);
      for (final value in entry.value) {
        final result = _normalizeQueryCandidate(
          value,
          requireExtension: requireExtension,
        );
        if (result != null) {
          return result;
        }
      }
    }
    return null;
  }

  String? _normalizeQueryCandidate(
    String value, {
    required bool requireExtension,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        const <String>{
          '0',
          '1',
          'true',
          'false',
          'download',
        }.contains(trimmed.toLowerCase())) {
      return null;
    }
    final nestedUri = Uri.tryParse(trimmed);
    String? candidate;
    if (nestedUri != null &&
        nestedUri.hasScheme &&
        nestedUri.pathSegments.isNotEmpty) {
      candidate = _normalizeCandidate(nestedUri.pathSegments.last);
    } else {
      candidate = _normalizeCandidate(trimmed);
    }
    if (candidate == null ||
        (requireExtension && !_hasLikelyFileExtension(candidate))) {
      return null;
    }
    return candidate;
  }

  bool _hasLikelyFileExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot >= 0 && dot < fileName.length - 1;
  }

  String? _fileNameFromPath(Uri uri) {
    if (uri.pathSegments.isEmpty) {
      return null;
    }
    return _normalizeCandidate(uri.pathSegments.last);
  }

  String? _normalizeCandidate(String? value) {
    final trimmed = value?.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    var decoded = trimmed;
    if (RegExp(r'%[0-9a-fA-F]{2}').hasMatch(trimmed)) {
      try {
        decoded = Uri.decodeComponent(trimmed);
      } on ArgumentError {
        decoded = trimmed;
      }
    }
    return _sanitizeUntrusted(decoded);
  }

  String _sanitizeUntrusted(String name) {
    final leafName = name.replaceAll('\u0000', '').split(RegExp(r'[\\/]')).last;
    return sanitize(leafName);
  }

  String? _decodeExtendedValue(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final parts = trimmed.split("'");
    final encoded = parts.length >= 3 ? parts.sublist(2).join("'") : trimmed;
    try {
      return Uri.decodeComponent(encoded);
    } on ArgumentError {
      return null;
    }
  }

  String _withMimeExtension(
    String fileName,
    String? mimeType, {
    bool replaceBinary = false,
  }) {
    final extension = _extensionForMimeType(mimeType);
    if (extension == null) {
      return fileName;
    }
    final dot = fileName.lastIndexOf('.');
    if (dot > 0) {
      if (!replaceBinary || fileName.substring(dot).toLowerCase() != '.bin') {
        return fileName;
      }
      return '${fileName.substring(0, dot)}$extension';
    }
    return '$fileName$extension';
  }

  String? _extensionForMimeType(String? mimeType) {
    final normalized = mimeType?.split(';').first.trim().toLowerCase();
    return const <String, String>{
      'application/zip': '.zip',
      'application/x-zip-compressed': '.zip',
      'application/vnd.android.package-archive': '.apk',
      'application/pdf': '.pdf',
      'application/x-7z-compressed': '.7z',
      'application/vnd.rar': '.rar',
      'application/x-rar-compressed': '.rar',
      'application/gzip': '.gz',
      'application/x-tar': '.tar',
      'application/json': '.json',
      'text/plain': '.txt',
      'text/csv': '.csv',
      'text/html': '.html',
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'image/gif': '.gif',
      'image/webp': '.webp',
      'audio/mpeg': '.mp3',
      'audio/mp4': '.m4a',
      'video/mp4': '.mp4',
      'video/webm': '.webm',
    }[normalized];
  }

  bool _isGenericFileName(String fileName) {
    final normalized = fileName.trim().toLowerCase();
    final dot = normalized.lastIndexOf('.');
    return dot <= 0 ||
        normalized.substring(dot) == '.bin' ||
        normalized.startsWith('download_');
  }

  String _defaultFileName() {
    return 'download_${_now().millisecondsSinceEpoch}.bin';
  }
}
