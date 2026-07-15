import 'package:flutter/services.dart';

class RuntimeLogSanitizer {
  const RuntimeLogSanitizer();

  static const Set<String> _sensitiveMetadataKeys = <String>{
    'authorization',
    'clipboard',
    'config',
    'content',
    'cookie',
    'credentials',
    'password',
    'payload',
    'proxyconfig',
    'secret',
    'token',
  };
  static final RegExp _nonLetterPattern = RegExp(r'[^a-z]');
  static final RegExp _urlPattern = RegExp(
    r"""[A-Za-z][A-Za-z0-9+.-]*://[^\s<>"']+""",
  );
  static final RegExp _authorizationHeaderPattern = RegExp(
    r'\b(Bearer|Basic)\s+\S+',
    caseSensitive: false,
  );
  static final RegExp _sensitiveAssignmentPattern = RegExp(
    r'''("?(?:password|token|secret|cookie|authorization)"?\s*[:=]\s*)("[^"]*"|[^,\s}]+)''',
    caseSensitive: false,
  );

  String sanitizeMessage(String message) {
    return _sanitizeText(message, maxLength: 4000);
  }

  String sanitizeStackTrace(StackTrace stackTrace) {
    return _sanitizeText(stackTrace.toString(), maxLength: 12000);
  }

  Object sanitizeError(Object error) {
    if (error is PlatformException) {
      return _sanitizeText(
        'PlatformException(${error.code}): ${error.message ?? 'No message'}',
        maxLength: 2000,
      );
    }
    return _sanitizeText(error.toString(), maxLength: 2000);
  }

  Map<String, Object?>? sanitizeMetadata(Map<String, Object?>? metadata) {
    if (metadata == null || metadata.isEmpty) {
      return metadata;
    }
    return <String, Object?>{
      for (final entry in metadata.entries.take(50))
        entry.key: _sanitizeMetadataValue(entry.key, entry.value, depth: 0),
    };
  }

  Object? _sanitizeMetadataValue(
    String key,
    Object? value, {
    required int depth,
  }) {
    if (_isSensitiveMetadataKey(key)) {
      return '<redacted>';
    }
    if (value == null || value is num || value is bool) {
      return value;
    }
    if (value is String) {
      return _sanitizeText(value, maxLength: 1000);
    }
    if (depth >= 3) {
      return '<truncated>';
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries.take(30))
          entry.key.toString(): _sanitizeMetadataValue(
            entry.key.toString(),
            entry.value,
            depth: depth + 1,
          ),
      };
    }
    if (value is Iterable) {
      return value
          .take(30)
          .map((item) => _sanitizeMetadataValue('', item, depth: depth + 1))
          .toList(growable: false);
    }
    return _sanitizeText(value.toString(), maxLength: 1000);
  }

  bool _isSensitiveMetadataKey(String key) {
    final normalized = key.toLowerCase().replaceAll(_nonLetterPattern, '');
    if (_sensitiveMetadataKeys.contains(normalized)) {
      return true;
    }
    return normalized.endsWith('apikey') ||
        normalized.endsWith('clipboardcontent') ||
        normalized.endsWith('cookievalue') ||
        normalized.endsWith('credential') ||
        normalized.endsWith('password') ||
        normalized.endsWith('payload') ||
        normalized.endsWith('secret') ||
        normalized.endsWith('streamurl') ||
        normalized.endsWith('token') ||
        normalized.endsWith('uploadkey');
  }

  String _sanitizeText(String value, {required int maxLength}) {
    final inputLimit = maxLength * 4;
    final boundedValue = value.length <= inputLimit
        ? value
        : value.substring(0, inputLimit);
    var sanitized = boundedValue.replaceAllMapped(_urlPattern, (match) {
      final rawUrl = match.group(0)!;
      final uri = Uri.tryParse(rawUrl);
      final scheme =
          uri?.scheme.toLowerCase() ??
          rawUrl.substring(0, rawUrl.indexOf(':')).toLowerCase();
      if (uri == null || (scheme != 'http' && scheme != 'https')) {
        return '$scheme://<redacted>';
      }
      return Uri(
        scheme: scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
      ).toString();
    });
    sanitized = sanitized.replaceAllMapped(
      _authorizationHeaderPattern,
      (match) => '${match.group(1)} <redacted>',
    );
    sanitized = sanitized.replaceAllMapped(
      _sensitiveAssignmentPattern,
      (match) => '${match.group(1)}<redacted>',
    );
    if (sanitized.length <= maxLength) {
      return sanitized;
    }
    return '${sanitized.substring(0, maxLength)}…';
  }
}
