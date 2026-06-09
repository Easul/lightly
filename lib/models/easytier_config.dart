class EasyTierPortMapping {
  const EasyTierPortMapping({required this.port, this.remark = ''});

  final int port;
  final String remark;

  EasyTierPortMapping copyWith({int? port, String? remark}) {
    return EasyTierPortMapping(
      port: port ?? this.port,
      remark: remark ?? this.remark,
    );
  }

  String toPortForward() {
    return 'tcp://0.0.0.0:$port/127.0.0.1:$port';
  }

  factory EasyTierPortMapping.fromJson(Map<String, dynamic> json) {
    return EasyTierPortMapping(
      port: json['port'] as int? ?? 0,
      remark: json['remark'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'port': port, 'remark': remark};
  }
}

class EasyTierConfig {
  final String instanceName;
  final String networkName;
  final String? networkSecret;
  final String? ipv4;
  final bool dhcp;
  final List<String> peers;
  final List<String> peerRemarks;
  final int? activePeerIndex;
  final List<String> listeners;
  final int? socks5Port;
  final bool enableP2p;
  final String? hostname;
  final bool noTun;
  final bool enableKcpProxy;
  final bool enableQuicProxy;
  final List<String> portForwards;
  final List<EasyTierPortMapping> portMappings;

  EasyTierConfig({
    required this.instanceName,
    required this.networkName,
    this.networkSecret,
    this.ipv4,
    this.dhcp = false,
    this.peers = const [],
    this.peerRemarks = const [],
    this.activePeerIndex,
    this.listeners = const [],
    this.socks5Port,
    this.enableP2p = true,
    this.hostname,
    this.noTun = false,
    this.enableKcpProxy = false,
    this.enableQuicProxy = false,
    this.portForwards = const [],
    this.portMappings = const [],
  });

  EasyTierConfig copyWith({
    String? instanceName,
    String? networkName,
    String? networkSecret,
    String? ipv4,
    bool? dhcp,
    List<String>? peers,
    List<String>? peerRemarks,
    int? activePeerIndex,
    List<String>? listeners,
    int? socks5Port,
    bool? enableP2p,
    String? hostname,
    bool? noTun,
    bool? enableKcpProxy,
    bool? enableQuicProxy,
    List<String>? portForwards,
    List<EasyTierPortMapping>? portMappings,
  }) {
    return EasyTierConfig(
      instanceName: instanceName ?? this.instanceName,
      networkName: networkName ?? this.networkName,
      networkSecret: networkSecret ?? this.networkSecret,
      ipv4: ipv4 ?? this.ipv4,
      dhcp: dhcp ?? this.dhcp,
      peers: peers ?? this.peers,
      peerRemarks: peerRemarks ?? this.peerRemarks,
      activePeerIndex: activePeerIndex ?? this.activePeerIndex,
      listeners: listeners ?? this.listeners,
      socks5Port: socks5Port ?? this.socks5Port,
      enableP2p: enableP2p ?? this.enableP2p,
      hostname: hostname ?? this.hostname,
      noTun: noTun ?? this.noTun,
      enableKcpProxy: enableKcpProxy ?? this.enableKcpProxy,
      enableQuicProxy: enableQuicProxy ?? this.enableQuicProxy,
      portForwards: portForwards ?? this.portForwards,
      portMappings: portMappings ?? this.portMappings,
    );
  }

  String toToml() {
    final buffer = StringBuffer();

    buffer.writeln('instance_name = "$instanceName"');
    final effectiveHostname = (hostname != null && hostname!.trim().isNotEmpty)
        ? hostname!.trim()
        : instanceName;
    buffer.writeln('hostname = "$effectiveHostname"');

    if (dhcp) {
      buffer.writeln('dhcp = true');
    } else if (ipv4 != null && ipv4!.isNotEmpty) {
      buffer.writeln('ipv4 = "$ipv4"');
    }

    final activePeer = _activePeerUri();
    if (activePeer != null) {
      buffer.writeln('');
      buffer.writeln('[[peer]]');
      buffer.writeln('uri = "$activePeer"');
    }

    if (listeners.isNotEmpty) {
      buffer.writeln('');
      final encodedListeners = listeners
          .map((listener) => '"$listener"')
          .join(', ');
      buffer.writeln('listeners = [$encodedListeners]');
    }

    if (socks5Port != null) {
      buffer.writeln('');
      buffer.writeln('socks5_proxy = "socks5://127.0.0.1:$socks5Port"');
    }

    final effectivePortForwards = _effectivePortForwards();
    if (effectivePortForwards.isNotEmpty) {
      buffer.writeln('');
      for (final forward in effectivePortForwards) {
        final config = _parsePortForward(forward);
        if (config == null) {
          continue;
        }
        buffer.writeln('[[port_forward]]');
        buffer.writeln('bind_addr = "${config.bindAddr}"');
        buffer.writeln('dst_addr = "${config.dstAddr}"');
        buffer.writeln('proto = "${config.proto}"');
        buffer.writeln('');
      }
    }

    buffer.writeln('');
    buffer.writeln('[network_identity]');
    buffer.writeln('network_name = "$networkName"');
    if (networkSecret != null && networkSecret!.isNotEmpty) {
      buffer.writeln('network_secret = "$networkSecret"');
    } else {
      buffer.writeln('network_secret = ""');
    }

    buffer.writeln('');
    buffer.writeln('[flags]');
    buffer.writeln('disable_p2p = ${!enableP2p}');
    if (noTun) {
      buffer.writeln('no_tun = true');
    }
    if (enableKcpProxy) {
      buffer.writeln('enable_kcp_proxy = true');
    }
    if (enableQuicProxy) {
      buffer.writeln('enable_quic_proxy = true');
    }

    return buffer.toString();
  }

  factory EasyTierConfig.fromJson(Map<String, dynamic> json) {
    return EasyTierConfig(
      instanceName: json['instanceName'] as String,
      networkName: json['networkName'] as String,
      networkSecret: json['networkSecret'] as String?,
      ipv4: json['ipv4'] as String?,
      dhcp: json['dhcp'] as bool? ?? false,
      peers: (json['peers'] as List<dynamic>?)?.cast<String>() ?? [],
      peerRemarks:
          (json['peerRemarks'] as List<dynamic>?)?.cast<String>() ?? [],
      activePeerIndex: json['activePeerIndex'] as int?,
      listeners: (json['listeners'] as List<dynamic>?)?.cast<String>() ?? [],
      socks5Port: json['socks5Port'] as int?,
      enableP2p: json['enableP2p'] as bool? ?? true,
      hostname: json['hostname'] as String?,
      noTun: json['noTun'] as bool? ?? false,
      enableKcpProxy: json['enableKcpProxy'] as bool? ?? false,
      enableQuicProxy: json['enableQuicProxy'] as bool? ?? false,
      portForwards:
          (json['portForwards'] as List<dynamic>?)?.cast<String>() ?? [],
      portMappings:
          (json['portMappings'] as List<dynamic>?)
              ?.map(
                (item) => EasyTierPortMapping.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .where((mapping) => mapping.port > 0 && mapping.port < 65536)
              .toList() ??
          const <EasyTierPortMapping>[],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'instanceName': instanceName,
      'networkName': networkName,
      'networkSecret': networkSecret,
      'ipv4': ipv4,
      'dhcp': dhcp,
      'peers': peers,
      'peerRemarks': peerRemarks,
      'activePeerIndex': activePeerIndex,
      'listeners': listeners,
      'socks5Port': socks5Port,
      'enableP2p': enableP2p,
      'hostname': hostname,
      'noTun': noTun,
      'enableKcpProxy': enableKcpProxy,
      'enableQuicProxy': enableQuicProxy,
      'portForwards': portForwards,
      'portMappings': portMappings.map((mapping) => mapping.toJson()).toList(),
    };
  }

  List<String> _effectivePortForwards() {
    final forwards = <String>[
      ...portForwards,
      ...portMappings
          .where((mapping) => mapping.port > 0 && mapping.port < 65536)
          .map((mapping) => mapping.toPortForward()),
    ];
    return forwards.toSet().toList();
  }

  String? _activePeerUri() {
    if (peers.isEmpty) return null;
    final index = activePeerIndex ?? 0;
    if (index < 0 || index >= peers.length) {
      return peers.first;
    }
    return peers[index];
  }

  _ParsedPortForward? _parsePortForward(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty || !uri.hasPort) {
      return null;
    }
    final dst = uri.pathSegments.join('/');
    if (dst.isEmpty) {
      return null;
    }
    return _ParsedPortForward(
      proto: uri.scheme,
      bindAddr: '${uri.host}:${uri.port}',
      dstAddr: dst,
    );
  }
}

class _ParsedPortForward {
  const _ParsedPortForward({
    required this.proto,
    required this.bindAddr,
    required this.dstAddr,
  });

  final String proto;
  final String bindAddr;
  final String dstAddr;
}
