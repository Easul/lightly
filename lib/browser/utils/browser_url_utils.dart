String? normalizeBrowserUrl(String rawValue) {
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  if (RegExp(r'[\s\u4e00-\u9fa5]').hasMatch(trimmed)) {
    return null;
  }

  final withScheme = trimmed.contains('://')
      ? trimmed
      : _shouldPreferHttp(trimmed)
      ? 'http://$trimmed'
      : 'https://$trimmed';
  final uri = Uri.tryParse(withScheme);
  if (uri == null ||
      !uri.hasScheme ||
      (uri.host.isEmpty && uri.scheme != 'file')) {
    return null;
  }

  const allowedSchemes = {'http', 'https', 'file'};
  if (!allowedSchemes.contains(uri.scheme.toLowerCase())) {
    return null;
  }

  if (uri.scheme != 'file' && !isDirectHostInput(uri.host)) {
    return null;
  }

  return uri.toString();
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
