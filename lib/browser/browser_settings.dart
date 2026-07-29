import '../features/proxy/domain/proxy_configuration.dart';
import '../features/proxy/domain/proxy_protocol.dart';

export '../features/proxy/domain/proxy_protocol.dart' show BrowserProxyProtocol;

class BrowserProxyNode {
  const BrowserProxyNode({
    required this.id,
    required this.name,
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
  });

  final String id;
  final String name;
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

  String get proxyProtocol => BrowserProxyProtocol.normalize(proxyScheme);

  BrowserProxyNode copyWith({
    String? id,
    String? name,
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
  }) {
    return BrowserProxyNode(
      id: id ?? this.id,
      name: name ?? this.name,
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'proxyHost': proxyHost,
      'proxyPort': proxyPort,
      'proxyScheme': proxyProtocol,
      'proxyUuid': proxyUuid,
      'proxyTlsEnabled': proxyTlsEnabled,
      'proxyTlsInsecure': proxyTlsInsecure,
      'proxyServerName': proxyServerName,
      'proxyTransportType': proxyTransportType,
      'proxyTransportPath': proxyTransportPath,
      'proxyTransportHost': proxyTransportHost,
      'proxyPacketEncoding': proxyPacketEncoding,
    };
  }

  factory BrowserProxyNode.fromJson(Map<String, dynamic> json) {
    return BrowserProxyNode(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
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
    );
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
    required this.proxyNodes,
    required this.selectedProxyNodeId,
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
    required this.webDebugConsoleEnabled,
    required this.desktopModeEnabled,
    required this.desktopUserAgentOverride,
    required this.appCacheAutoClearEnabled,
    required this.appCacheAutoClearIntervalHours,
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
  final List<BrowserProxyNode> proxyNodes;
  final String? selectedProxyNodeId;
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
  final bool webDebugConsoleEnabled;
  final bool desktopModeEnabled;
  final String desktopUserAgentOverride;
  final bool appCacheAutoClearEnabled;
  final int appCacheAutoClearIntervalHours;

  String get normalizedDesktopUserAgentOverride {
    return desktopUserAgentOverride.trim();
  }

  String get normalizedNativeVideoParserApiBaseUrl {
    final trimmed = nativeVideoParserApiBaseUrl.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }

  bool get canResolveYoutubeWithNativePlayer {
    return nativeVideoPlayerEnabled;
  }

  String get proxyProtocol => BrowserProxyProtocol.normalize(proxyScheme);

  ProxyConfiguration get proxyConfiguration => ProxyConfiguration(
    proxyEnabled: proxyEnabled,
    proxyHost: proxyHost,
    proxyPort: proxyPort,
    proxyProtocol: proxyProtocol,
    proxyUuid: proxyUuid,
    proxyTlsEnabled: proxyTlsEnabled,
    proxyTlsInsecure: proxyTlsInsecure,
    proxyServerName: proxyServerName,
    proxyTransportType: proxyTransportType,
    proxyTransportPath: proxyTransportPath,
    proxyTransportHost: proxyTransportHost,
    proxyPacketEncoding: proxyPacketEncoding,
    proxyBypassDomainList: proxyBypassDomainList,
    localProxyPort: localProxyPort,
  );

  factory BrowserSettings.defaults() {
    return const BrowserSettings(
      homepageUrl: 'https://www.google.com',
      proxyEnabled: false,
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
      proxyNodes: <BrowserProxyNode>[],
      selectedProxyNodeId: null,
      proxyBypassDomains: '',
      localProxyPort: 23333,
      localHttpServerEnabled: false,
      localHttpRootPath: '/storage/emulated/0/Download',
      localHttpServerPort: 3001,
      localHttpBindAllInterfaces: false,
      localHttpUploadKey: '',
      nativeVideoPlayerEnabled: false,
      nativeVideoParserApiBaseUrl: 'https://parser.example.com',
      openNewWindowInTab: true,
      webDebugConsoleEnabled: false,
      desktopModeEnabled: false,
      desktopUserAgentOverride: '',
      appCacheAutoClearEnabled: false,
      appCacheAutoClearIntervalHours: 24,
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
    List<BrowserProxyNode>? proxyNodes,
    String? selectedProxyNodeId,
    bool clearSelectedProxyNodeId = false,
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
    bool? webDebugConsoleEnabled,
    bool? desktopModeEnabled,
    String? desktopUserAgentOverride,
    bool? appCacheAutoClearEnabled,
    int? appCacheAutoClearIntervalHours,
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
      proxyNodes: proxyNodes ?? this.proxyNodes,
      selectedProxyNodeId: clearSelectedProxyNodeId
          ? null
          : selectedProxyNodeId ?? this.selectedProxyNodeId,
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
      webDebugConsoleEnabled:
          webDebugConsoleEnabled ?? this.webDebugConsoleEnabled,
      desktopModeEnabled: desktopModeEnabled ?? this.desktopModeEnabled,
      desktopUserAgentOverride:
          desktopUserAgentOverride ?? this.desktopUserAgentOverride,
      appCacheAutoClearEnabled:
          appCacheAutoClearEnabled ?? this.appCacheAutoClearEnabled,
      appCacheAutoClearIntervalHours:
          appCacheAutoClearIntervalHours ?? this.appCacheAutoClearIntervalHours,
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
      'proxyNodes': proxyNodes.map((node) => node.toJson()).toList(),
      'selectedProxyNodeId': selectedProxyNodeId,
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
      'webDebugConsoleEnabled': webDebugConsoleEnabled,
      'desktopModeEnabled': desktopModeEnabled,
      'desktopUserAgentOverride': desktopUserAgentOverride,
      'appCacheAutoClearEnabled': appCacheAutoClearEnabled,
      'appCacheAutoClearIntervalHours': appCacheAutoClearIntervalHours,
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
      proxyNodes: (json['proxyNodes'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map(
            (item) =>
                BrowserProxyNode.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((node) => node.id.isNotEmpty)
          .toList(),
      selectedProxyNodeId: json['selectedProxyNodeId'] as String?,
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
      webDebugConsoleEnabled: json['webDebugConsoleEnabled'] as bool? ?? false,
      desktopModeEnabled: json['desktopModeEnabled'] as bool? ?? false,
      desktopUserAgentOverride:
          json['desktopUserAgentOverride'] as String? ?? '',
      appCacheAutoClearEnabled:
          json['appCacheAutoClearEnabled'] as bool? ?? false,
      appCacheAutoClearIntervalHours:
          (json['appCacheAutoClearIntervalHours'] as num?)?.toInt() ?? 24,
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
    return proxyConfiguration.shouldBypassProxyForUri(uri);
  }

  String? get proxyValidationError {
    return proxyConfiguration.validationError;
  }

  bool get hasUsableProxy => proxyConfiguration.hasUsableProxy;

  bool get shouldApplyProxy => proxyConfiguration.shouldApplyProxy;

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
