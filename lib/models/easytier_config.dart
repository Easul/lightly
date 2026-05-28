class EasyTierConfig {
  final String instanceName;
  final String networkName;
  final String? networkSecret;
  final String? ipv4;
  final bool dhcp;
  final List<String> peers;
  final List<String> listeners;
  final int? socks5Port;
  final bool enableP2p;
  final bool needP2p;
  final String? hostname;

  EasyTierConfig({
    required this.instanceName,
    required this.networkName,
    this.networkSecret,
    this.ipv4,
    this.dhcp = false,
    this.peers = const [],
    this.listeners = const [],
    this.socks5Port,
    this.enableP2p = true,
    this.needP2p = false,
    this.hostname,
  });

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

    if (peers.isNotEmpty) {
      for (final peer in peers) {
        buffer.writeln('');
        buffer.writeln('[[peer]]');
        buffer.writeln('uri = "$peer"');
      }
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
    buffer.writeln('need_p2p = $needP2p');

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
      listeners: (json['listeners'] as List<dynamic>?)?.cast<String>() ?? [],
      socks5Port: json['socks5Port'] as int?,
      enableP2p: json['enableP2p'] as bool? ?? true,
      needP2p: json['needP2p'] as bool? ?? false,
      hostname: json['hostname'] as String?,
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
      'listeners': listeners,
      'socks5Port': socks5Port,
      'enableP2p': enableP2p,
      'needP2p': needP2p,
      'hostname': hostname,
    };
  }
}
