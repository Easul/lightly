const _legacyImportedDocumentPrefixes = <String>[
  '/data/user/0/lightly.tool/files/imported_documents/',
  '/data/data/lightly.tool/files/imported_documents/',
];
const _externalImportedDocumentPrefix =
    '/storage/emulated/0/Android/data/lightly.tool/files/Documents/imported_documents/';

String? normalizeBrowserUrl(String rawValue) {
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final normalizedFileInput = _normalizeAndroidFileUrl(trimmed);

  final directUri = Uri.tryParse(normalizedFileInput);
  if (directUri != null && directUri.hasScheme) {
    final scheme = directUri.scheme.toLowerCase();
    if (scheme == 'file') {
      if (directUri.path.isEmpty) {
        return null;
      }
      return remapImportedDocumentFileUrl(directUri.toString());
    }
    if (scheme == 'content') {
      return directUri.toString();
    }
  }

  if (RegExp(r'[\s\u4e00-\u9fa5]').hasMatch(normalizedFileInput)) {
    return null;
  }

  final withScheme = normalizedFileInput.contains('://')
      ? normalizedFileInput
      : _shouldPreferHttp(normalizedFileInput)
      ? 'http://$normalizedFileInput'
      : 'https://$normalizedFileInput';
  final uri = Uri.tryParse(withScheme);
  if (uri == null ||
      !uri.hasScheme ||
      (uri.host.isEmpty && uri.scheme != 'file')) {
    return null;
  }

  const allowedSchemes = {'http', 'https', 'file', 'content'};
  if (!allowedSchemes.contains(uri.scheme.toLowerCase())) {
    return null;
  }

  if (uri.scheme != 'file' && !isDirectHostInput(uri.host)) {
    return null;
  }

  return uri.toString();
}

String remapImportedDocumentFileUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri?.scheme.toLowerCase() != 'file') {
    return url;
  }

  final path = uri?.path;
  if (path == null || path.isEmpty) {
    return url;
  }

  for (final prefix in _legacyImportedDocumentPrefixes) {
    if (path.startsWith(prefix)) {
      final relativePath = path.substring(prefix.length);
      return Uri.file(
        '$_externalImportedDocumentPrefix$relativePath',
      ).toString();
    }
  }

  return url;
}

String _normalizeAndroidFileUrl(String rawValue) {
  final lowerCased = rawValue.toLowerCase();
  if (!lowerCased.startsWith('file://') || lowerCased.startsWith('file:///')) {
    return rawValue;
  }

  final remainder = rawValue.substring('file://'.length);
  if (remainder.startsWith('/')) {
    return 'file://$remainder';
  }

  if (remainder.startsWith('storage/') || remainder.startsWith('sdcard/')) {
    return 'file:///$remainder';
  }

  return rawValue;
}

bool _shouldPreferHttp(String rawValue) {
  final uri = Uri.tryParse('http://$rawValue');
  final host = uri?.host ?? rawValue;
  return host == 'localhost' || host == '::1' || _isPrivateIpv4(host);
}

bool _isPrivateIpv4(String host) {
  final match = RegExp(
    r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
  ).firstMatch(host);
  if (match == null) {
    return false;
  }

  final octets = List<int>.generate(4, (index) {
    return int.parse(match.group(index + 1)!);
  });
  if (octets.any((octet) => octet < 0 || octet > 255)) {
    return false;
  }

  if (octets[0] == 10 || octets[0] == 127) {
    return true;
  }
  if (octets[0] == 192 && octets[1] == 168) {
    return true;
  }
  if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) {
    return true;
  }
  return false;
}

bool isDirectHostInput(String host) {
  final normalized = host.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  if (normalized == 'localhost' || normalized == '::1') {
    return true;
  }
  if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(normalized)) {
    return true;
  }
  return normalized.contains('.');
}

bool isLocalBrowserUrl(String? rawUrl) {
  if (rawUrl == null || rawUrl.trim().isEmpty) {
    return false;
  }

  final uri = Uri.tryParse(rawUrl);
  if (uri == null) {
    return false;
  }

  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'file' || scheme == 'content') {
    return true;
  }
  if (!(scheme == 'http' || scheme == 'https')) {
    return false;
  }

  final host = uri.host.toLowerCase();
  if (host.isEmpty) {
    return false;
  }
  return host == 'localhost' || host == '::1' || _isPrivateIpv4(host);
}
