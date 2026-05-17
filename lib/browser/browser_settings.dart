class BrowserProxyProtocol {
  static const String http = 'http';
  static const String vless = 'vless';
  static const String hysteria2 = 'hysteria2';

  static const List<String> values = [http, vless, hysteria2];

  static String normalize(String? value) {
    final normalizedValue = (value ?? '').trim().toLowerCase().replaceFirst(
      RegExp(r':/*$'),
      '',
    );

    switch (normalizedValue) {
      case 'http':
      case 'https':
        return http;
      case vless:
        return vless;
      case 'hy2':
      case hysteria2:
        return hysteria2;
      default:
        return http;
    }
  }

  static String label(String protocol) {
    switch (normalize(protocol)) {
      case http:
        return 'HTTP';
      case vless:
        return 'VLESS';
      case hysteria2:
        return 'Hysteria2';
    }

    return 'HTTP';
  }
}

class BrowserSettings {
  static const List<String> _builtInProxyBypassDomains = <String>[
    'google.com',
    'gstatic.com',
    'googleapis.com',
    'example-site.com',
    'challenges.cloudflare.com',
  ];

  const BrowserSettings({
    required this.homepageUrl,
    required this.proxyEnabled,
    required this.proxyHost,
    required this.proxyPort,
    required this.proxyScheme,
    required this.proxyUuid,
    required this.proxyTlsEnabled,
    required this.proxyTlsInsecure,
    required this.proxyServerName,
    required this.proxyTransportType,
    required this.proxyTransportPath,
    required this.proxyTransportHost,
    required this.proxyPacketEncoding,
    required this.proxyBypassDomains,
    required this.localProxyPort,
    required this.localHttpServerEnabled,
    required this.localHttpRootPath,
    required this.localHttpServerPort,
    required this.localHttpBindAllInterfaces,
    required this.localHttpUploadKey,
    required this.nativeVideoPlayerEnabled,
    required this.nativeVideoParserApiBaseUrl,
    required this.openNewWindowInTab,
  });

  final String homepageUrl;
  final bool proxyEnabled;
  final String proxyHost;
  final int? proxyPort;
  final String proxyScheme;
  final String proxyUuid;
  final bool proxyTlsEnabled;
  final bool proxyTlsInsecure;
  final String proxyServerName;
  final String proxyTransportType;
  final String proxyTransportPath;
  final String proxyTransportHost;
  final String proxyPacketEncoding;
  final String proxyBypassDomains;
  final int? localProxyPort;
  final bool localHttpServerEnabled;
  final String localHttpRootPath;
  final int? localHttpServerPort;
  final bool localHttpBindAllInterfaces;
  final String localHttpUploadKey;
  final bool nativeVideoPlayerEnabled;
  final String nativeVideoParserApiBaseUrl;
  final bool openNewWindowInTab;

  String get normalizedNativeVideoParserApiBaseUrl {
    final trimmed = nativeVideoParserApiBaseUrl.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }

  bool get canResolveYoutubeWithNativePlayer {
    return nativeVideoPlayerEnabled &&
        normalizedNativeVideoParserApiBaseUrl.isNotEmpty;
  }

  String get proxyProtocol => BrowserProxyProtocol.normalize(proxyScheme);

  factory BrowserSettings.defaults() {
    return const BrowserSettings(
      homepageUrl: 'https://www.google.com',
      proxyEnabled: true,
      proxyHost: '',
      proxyPort: null,
      proxyScheme: BrowserProxyProtocol.http,
      proxyUuid: '',
      proxyTlsEnabled: false,
      proxyTlsInsecure: false,
      proxyServerName: '',
      proxyTransportType: '',
      proxyTransportPath: '',
      proxyTransportHost: '',
      proxyPacketEncoding: '',
      proxyBypassDomains: '',
      localProxyPort: 23333,
      localHttpServerEnabled: true,
      localHttpRootPath: '/storage/emulated/0/Download',
      localHttpServerPort: 3001,
      localHttpBindAllInterfaces: false,
      localHttpUploadKey: '',
      nativeVideoPlayerEnabled: false,
      nativeVideoParserApiBaseUrl: 'https://parser.example.com',
      openNewWindowInTab: true,
    );
  }

  BrowserSettings copyWith({
    String? homepageUrl,
    bool? proxyEnabled,
    String? proxyHost,
    int? proxyPort,
    bool clearProxyPort = false,
    String? proxyScheme,
    String? proxyUuid,
    bool? proxyTlsEnabled,
    bool? proxyTlsInsecure,
    String? proxyServerName,
    String? proxyTransportType,
    String? proxyTransportPath,
    String? proxyTransportHost,
    String? proxyPacketEncoding,
    String? proxyBypassDomains,
    int? localProxyPort,
    bool clearLocalProxyPort = false,
    bool? localHttpServerEnabled,
    String? localHttpRootPath,
    int? localHttpServerPort,
    bool clearLocalHttpServerPort = false,
    bool? localHttpBindAllInterfaces,
    String? localHttpUploadKey,
    bool? nativeVideoPlayerEnabled,
    String? nativeVideoParserApiBaseUrl,
    bool? openNewWindowInTab,
  }) {
    return BrowserSettings(
      homepageUrl: homepageUrl ?? this.homepageUrl,
      proxyEnabled: proxyEnabled ?? this.proxyEnabled,
      proxyHost: proxyHost ?? this.proxyHost,
      proxyPort: clearProxyPort ? null : proxyPort ?? this.proxyPort,
      proxyScheme: proxyScheme ?? this.proxyScheme,
      proxyUuid: proxyUuid ?? this.proxyUuid,
      proxyTlsEnabled: proxyTlsEnabled ?? this.proxyTlsEnabled,
      proxyTlsInsecure: proxyTlsInsecure ?? this.proxyTlsInsecure,
      proxyServerName: proxyServerName ?? this.proxyServerName,
      proxyTransportType: proxyTransportType ?? this.proxyTransportType,
      proxyTransportPath: proxyTransportPath ?? this.proxyTransportPath,
      proxyTransportHost: proxyTransportHost ?? this.proxyTransportHost,
      proxyPacketEncoding: proxyPacketEncoding ?? this.proxyPacketEncoding,
      proxyBypassDomains: proxyBypassDomains ?? this.proxyBypassDomains,
      localProxyPort: clearLocalProxyPort
          ? null
          : localProxyPort ?? this.localProxyPort,
      localHttpServerEnabled:
          localHttpServerEnabled ?? this.localHttpServerEnabled,
      localHttpRootPath: localHttpRootPath ?? this.localHttpRootPath,
      localHttpServerPort: clearLocalHttpServerPort
          ? null
          : localHttpServerPort ?? this.localHttpServerPort,
      localHttpBindAllInterfaces:
          localHttpBindAllInterfaces ?? this.localHttpBindAllInterfaces,
      localHttpUploadKey: localHttpUploadKey ?? this.localHttpUploadKey,
      nativeVideoPlayerEnabled:
          nativeVideoPlayerEnabled ?? this.nativeVideoPlayerEnabled,
      nativeVideoParserApiBaseUrl:
          nativeVideoParserApiBaseUrl ?? this.nativeVideoParserApiBaseUrl,
      openNewWindowInTab: openNewWindowInTab ?? this.openNewWindowInTab,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'homepageUrl': homepageUrl,
      'proxyEnabled': proxyEnabled,
      'proxyHost': proxyHost,
      'proxyPort': proxyPort,
      'proxyScheme': proxyProtocol,
      'proxyProtocol': proxyProtocol,
      'proxyUuid': proxyUuid,
      'proxyTlsEnabled': proxyTlsEnabled,
      'proxyTlsInsecure': proxyTlsInsecure,
      'proxyServerName': proxyServerName,
      'proxyTransportType': proxyTransportType,
      'proxyTransportPath': proxyTransportPath,
      'proxyTransportHost': proxyTransportHost,
      'proxyPacketEncoding': proxyPacketEncoding,
      'proxyBypassDomains': proxyBypassDomains,
      'localProxyPort': localProxyPort,
      'localHttpServerEnabled': localHttpServerEnabled,
      'localHttpRootPath': localHttpRootPath,
      'localHttpServerPort': localHttpServerPort,
      'localHttpBindAllInterfaces': localHttpBindAllInterfaces,
      'localHttpUploadKey': localHttpUploadKey,
      'nativeVideoPlayerEnabled': nativeVideoPlayerEnabled,
      'nativeVideoParserApiBaseUrl': nativeVideoParserApiBaseUrl,
      'openNewWindowInTab': openNewWindowInTab,
    };
  }

  factory BrowserSettings.fromJson(Map<String, dynamic> json) {
    return BrowserSettings(
      homepageUrl: json['homepageUrl'] as String? ?? 'https://www.google.com',
      proxyEnabled: json['proxyEnabled'] as bool? ?? false,
      proxyHost: json['proxyHost'] as String? ?? '',
      proxyPort: (json['proxyPort'] as num?)?.toInt(),
      proxyScheme: BrowserProxyProtocol.normalize(
        json['proxyProtocol'] as String? ?? json['proxyScheme'] as String?,
      ),
      proxyUuid:
          json['proxyUuid'] as String? ??
          (json['proxyPassword'] as String? ?? ''),
      proxyTlsEnabled: json['proxyTlsEnabled'] as bool? ?? false,
      proxyTlsInsecure: json['proxyTlsInsecure'] as bool? ?? false,
      proxyServerName: json['proxyServerName'] as String? ?? '',
      proxyTransportType: json['proxyTransportType'] as String? ?? '',
      proxyTransportPath: json['proxyTransportPath'] as String? ?? '',
      proxyTransportHost: json['proxyTransportHost'] as String? ?? '',
      proxyPacketEncoding: json['proxyPacketEncoding'] as String? ?? '',
      proxyBypassDomains: json['proxyBypassDomains'] as String? ?? '',
      localProxyPort: (json['localProxyPort'] as num?)?.toInt() ?? 23333,
      localHttpServerEnabled: json['localHttpServerEnabled'] as bool? ?? false,
      localHttpRootPath:
          json['localHttpRootPath'] as String? ??
          '/storage/emulated/0/Download',
      localHttpServerPort:
          (json['localHttpServerPort'] as num?)?.toInt() ?? 3001,
      localHttpBindAllInterfaces:
          json['localHttpBindAllInterfaces'] as bool? ?? false,
      localHttpUploadKey: json['localHttpUploadKey'] as String? ?? '',
      nativeVideoPlayerEnabled:
          json['nativeVideoPlayerEnabled'] as bool? ?? false,
      nativeVideoParserApiBaseUrl:
          json['nativeVideoParserApiBaseUrl'] as String? ??
          'https://parser.example.com',
      openNewWindowInTab: json['openNewWindowInTab'] as bool? ?? true,
    );
  }

  List<String> get proxyBypassDomainList => proxyBypassDomains
      .split(RegExp(r'[\n,;]+'))
      .map((entry) => entry.trim().toLowerCase())
      .where((entry) => entry.isNotEmpty)
      .followedBy(_builtInProxyBypassDomains)
      .toSet()
      .toList(growable: false);

  bool shouldBypassProxyForUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.isEmpty) {
      return true;
    }
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host.startsWith('127.')) {
      return true;
    }
    for (final pattern in proxyBypassDomainList) {
      if (host == pattern ||
          host.endsWith('.$pattern') ||
          host.contains(pattern)) {
        return true;
      }
    }
    return false;
  }

  String? get _proxyConfigurationError {
    if (proxyHost.trim().isEmpty) {
      return 'Proxy host is required';
    }

    if (proxyPort == null || proxyPort! <= 0) {
      return 'Proxy port must be a valid number';
    }

    if (localProxyPort != null &&
        (localProxyPort! <= 0 || localProxyPort! > 65535)) {
      return 'Local proxy port must be between 1 and 65535';
    }

    switch (proxyProtocol) {
      case BrowserProxyProtocol.http:
        return null;
      case BrowserProxyProtocol.vless:
        return proxyUuid.trim().isEmpty ? 'VLESS UUID is required' : null;
      case BrowserProxyProtocol.hysteria2:
        return proxyUuid.trim().isEmpty
            ? 'Hysteria2 password is required'
            : null;
    }

    return null;
  }

  String? get proxyValidationError {
    if (!proxyEnabled) {
      return null;
    }

    return _proxyConfigurationError;
  }

  bool get hasUsableProxy => _proxyConfigurationError == null;

  bool get shouldApplyProxy => proxyEnabled && hasUsableProxy;

  bool hasSameProxyConfiguration(BrowserSettings other) {
    return proxyEnabled == other.proxyEnabled &&
        proxyProtocol == other.proxyProtocol &&
        proxyHost.trim() == other.proxyHost.trim() &&
        proxyPort == other.proxyPort &&
        proxyUuid.trim() == other.proxyUuid.trim() &&
        proxyTlsEnabled == other.proxyTlsEnabled &&
        proxyTlsInsecure == other.proxyTlsInsecure &&
        proxyServerName.trim() == other.proxyServerName.trim() &&
        proxyTransportType.trim() == other.proxyTransportType.trim() &&
        proxyTransportPath.trim() == other.proxyTransportPath.trim() &&
        proxyTransportHost.trim() == other.proxyTransportHost.trim() &&
        proxyPacketEncoding.trim() == other.proxyPacketEncoding.trim() &&
        proxyBypassDomains.trim() == other.proxyBypassDomains.trim() &&
        localProxyPort == other.localProxyPort;
  }

  String? get localHttpServerValidationError {
    if (!localHttpServerEnabled) {
      return null;
    }
    if (localHttpRootPath.trim().isEmpty) {
      return '本地 HTTP 服务目录不能为空';
    }
    if (localHttpServerPort != null &&
        (localHttpServerPort! <= 0 || localHttpServerPort! > 65535)) {
      return '本地 HTTP 服务端口必须是 1-65535';
    }
    return null;
  }
}
