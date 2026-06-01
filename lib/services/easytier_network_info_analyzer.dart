import 'dart:convert';

class EasyTierNetworkInfoAnalyzer {
  const EasyTierNetworkInfoAnalyzer._();

  static String? extractInstanceIpv4(
    Map<String, dynamic>? networkInfo,
    String instanceName,
  ) {
    final instanceInfo = currentInstanceNetworkInfo(networkInfo, instanceName);
    return instanceInfo == null ? null : _decodeMyNodeIpv4(instanceInfo);
  }

  static Map<String, dynamic>? currentInstanceNetworkInfo(
    Map<String, dynamic>? networkInfo,
    String instanceName,
  ) {
    if (networkInfo == null) {
      return null;
    }

    final topLevelMap = networkInfo['map'];
    if (topLevelMap is! Map) {
      return networkInfo;
    }

    final normalizedInstanceName = instanceName.trim();
    if (normalizedInstanceName.isNotEmpty) {
      final current = topLevelMap[normalizedInstanceName];
      if (current is Map) {
        return Map<String, dynamic>.from(current);
      }
    }

    if (topLevelMap.isNotEmpty) {
      final firstValue = topLevelMap.values.first;
      if (firstValue is Map) {
        return Map<String, dynamic>.from(firstValue);
      }
    }

    return null;
  }

  static List<Map<String, String>> buildPeerSummaries(
    Map<String, dynamic>? networkInfo,
    String instanceName,
  ) {
    final instanceInfo = currentInstanceNetworkInfo(networkInfo, instanceName);
    if (instanceInfo == null) {
      return const <Map<String, String>>[];
    }

    final routeByPeerId = <int, Map<String, dynamic>>{};
    final rawRoutes = instanceInfo['routes'];
    if (rawRoutes is List) {
      for (final route in rawRoutes) {
        if (route is! Map) {
          continue;
        }
        final routeMap = Map<String, dynamic>.from(route);
        final peerId = (routeMap['peer_id'] as num?)?.toInt();
        if (peerId != null) {
          routeByPeerId[peerId] = routeMap;
        }
      }
    }

    final churnByPeerId = _buildPeerEventStats(instanceInfo['events']);
    final rawPeers = instanceInfo['peers'];
    if (rawPeers is! List) {
      if (routeByPeerId.isEmpty) {
        return const <Map<String, String>>[];
      }

      return routeByPeerId.values
          .where(
            (routeMap) =>
                routeMap['feature_flag'] is! Map ||
                routeMap['feature_flag']['is_public_server'] != true,
          )
          .map((routeMap) {
            final peerId = (routeMap['peer_id'] as num?)?.toInt() ?? 0;
            final hostname = (routeMap['hostname'] as String?)?.trim();
            final ipv4 = decodeIpv4(
              routeMap['ipv4_addr'] is Map
                  ? Map<String, dynamic>.from(routeMap['ipv4_addr'] as Map)
                  : null,
            );
            final mode = _describeRouteMode(routeMap, routeByPeerId);
            final status = _describePeerHealth(churnByPeerId[peerId]);
            return <String, String>{
              'name': (hostname == null || hostname.isEmpty)
                  ? '未命名设备'
                  : hostname,
              'ip': ipv4 ?? '未分配 IP',
              'latency': '${routeMap['path_latency'] ?? '-'} ms',
              'mode': mode,
              'status': status,
              'remoteReachable': _isRouteRemoteReachable(routeMap, ipv4)
                  ? 'true'
                  : 'false',
            };
          })
          .toList();
    }

    final peerById = <int, Map<String, dynamic>>{};
    for (final peer in rawPeers) {
      if (peer is! Map) {
        continue;
      }

      final peerMap = Map<String, dynamic>.from(peer);
      final peerId = (peerMap['peer_id'] as num?)?.toInt();
      if (peerId == null) {
        continue;
      }
      peerById[peerId] = peerMap;
    }

    final peers = <Map<String, String>>[];
    final routedPeerIds = <int>{};
    for (final routeMap in routeByPeerId.values) {
      final peerId = (routeMap['peer_id'] as num?)?.toInt();
      if (peerId == null) {
        continue;
      }
      final featureFlag = routeMap['feature_flag'];
      if (featureFlag is Map && featureFlag['is_public_server'] == true) {
        continue;
      }
      routedPeerIds.add(peerId);

      final peerMap = peerById[peerId];
      final hostname = (routeMap['hostname'] as String?)?.trim();
      final ipv4 = decodeIpv4(
        routeMap['ipv4_addr'] is Map
            ? Map<String, dynamic>.from(routeMap['ipv4_addr'] as Map)
            : null,
      );
      final mode = peerMap == null
          ? _describeRouteMode(routeMap, routeByPeerId)
          : _describePeerMode(peerMap, routeMap, routeByPeerId);
      final status = _describePeerHealth(churnByPeerId[peerId]);
      peers.add(<String, String>{
        'name': (hostname == null || hostname.isEmpty) ? '未命名设备' : hostname,
        'ip': ipv4 ?? '未分配 IP',
        'latency': '${routeMap['path_latency'] ?? '-'} ms',
        'mode': mode,
        'status': status,
        'peerId': '$peerId',
        'remoteReachable': _isRouteRemoteReachable(routeMap, ipv4)
            ? 'true'
            : 'false',
      });
    }

    for (final entry in peerById.entries) {
      if (routedPeerIds.contains(entry.key)) {
        continue;
      }
      final peerMap = entry.value;
      final hostname = (peerMap['hostname'] as String?)?.trim();
      final stats = churnByPeerId[entry.key];
      peers.add(<String, String>{
        'name': (hostname == null || hostname.isEmpty) ? '未命名设备' : hostname,
        'ip': '未连接',
        'latency': '-',
        'mode': '未形成可用路径',
        'status': (stats?['removed'] ?? 0) > 0 ? '已离线/中继不可用' : '等待连接',
        'peerId': '${entry.key}',
        'remoteReachable': 'false',
      });
    }

    return peers;
  }

  static List<String> buildDiagnostics(
    Map<String, dynamic>? networkInfo,
    String instanceName,
  ) {
    final instanceInfo = currentInstanceNetworkInfo(networkInfo, instanceName);
    if (instanceInfo == null) {
      return const <String>[];
    }

    final messages = <String>[];
    final myNodeInfo = instanceInfo['my_node_info'];
    if (myNodeInfo is Map<String, dynamic>) {
      final stunInfo = myNodeInfo['stun_info'];
      if (stunInfo is Map<String, dynamic>) {
        messages.add(
          'NAT 状态：UDP ${stunInfo['udp_nat_type'] ?? '-'} / TCP ${stunInfo['tcp_nat_type'] ?? '-'}',
        );
      }
      if (myNodeInfo['virtual_ipv4'] == null) {
        messages.add('当前尚未拿到虚拟 IPv4，通常意味着还没完成网络地址分配。');
      }
    }

    final churnStats = _buildPeerEventStats(instanceInfo['events']);
    for (final entry in churnStats.entries) {
      final removed = entry.value['removed'] ?? 0;
      if (removed >= 3) {
        messages.add('Peer ${entry.key} 最近频繁断开重连，可能存在打洞失败或中继不稳定。');
      }
    }

    final routes = instanceInfo['routes'];
    if (routes is List) {
      for (final route in routes) {
        if (route is! Map) {
          continue;
        }
        final routeMap = Map<String, dynamic>.from(route);
        final featureFlag = routeMap['feature_flag'];
        final cost = (routeMap['cost'] as num?)?.toInt() ?? 0;
        if (featureFlag is Map && featureFlag['is_public_server'] == true) {
          continue;
        }
        if (cost > 1) {
          final hostname = (routeMap['hostname'] as String?)?.trim() ?? '未知设备';
          messages.add('$hostname 当前走中继路径，尚未形成直连 P2P。');
        }
      }
    }

    if (messages.isEmpty) {
      messages.add('当前未发现明显异常，可继续观察延迟和连接模式。');
    }
    return messages;
  }

  static String formattedNetworkInfoText({
    required String? rawNetworkInfo,
    required Map<String, dynamic>? networkInfo,
    required String instanceName,
  }) {
    if (rawNetworkInfo != null && rawNetworkInfo.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawNetworkInfo);
        return const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        return rawNetworkInfo;
      }
    }

    final instanceInfo =
        currentInstanceNetworkInfo(networkInfo, instanceName) ?? networkInfo;
    if (instanceInfo == null) {
      return '暂无网络信息';
    }

    try {
      return const JsonEncoder.withIndent('  ').convert(instanceInfo);
    } catch (_) {
      return instanceInfo.toString();
    }
  }

  static String? _decodeMyNodeIpv4(Map<String, dynamic> instanceInfo) {
    final myNodeInfo = instanceInfo['my_node_info'];
    if (myNodeInfo is! Map) {
      return null;
    }
    return decodeIpv4(
      myNodeInfo['virtual_ipv4'] is Map
          ? Map<String, dynamic>.from(myNodeInfo['virtual_ipv4'] as Map)
          : null,
    );
  }

  static String? decodeIpv4(dynamic ipv4Object) {
    if (ipv4Object is! Map<String, dynamic>) {
      return null;
    }

    final address = ipv4Object['address'];
    if (address is! Map<String, dynamic>) {
      return null;
    }

    final rawAddr = address['addr'];
    if (rawAddr is! num) {
      return null;
    }

    final networkLength = (ipv4Object['network_length'] as num?)?.toInt();
    final normalized = rawAddr.toInt() & 0xffffffff;
    final ip = [
      (normalized >> 24) & 0xff,
      (normalized >> 16) & 0xff,
      (normalized >> 8) & 0xff,
      normalized & 0xff,
    ].join('.');

    return networkLength == null ? ip : '$ip/$networkLength';
  }

  static Map<int, Map<String, int>> _buildPeerEventStats(dynamic rawEvents) {
    final stats = <int, Map<String, int>>{};
    if (rawEvents is! List) {
      return stats;
    }

    for (final item in rawEvents) {
      if (item is! String) {
        continue;
      }
      try {
        final decoded = jsonDecode(item) as Map<String, dynamic>;
        final event = decoded['event'];
        if (event is! Map<String, dynamic>) {
          continue;
        }
        if (event.containsKey('PeerConnAdded')) {
          final payload = event['PeerConnAdded'];
          if (payload is Map<String, dynamic>) {
            final peerId = (payload['peer_id'] as num?)?.toInt();
            if (peerId != null) {
              final peerStats = stats.putIfAbsent(
                peerId,
                () => <String, int>{'added': 0, 'removed': 0},
              );
              peerStats['added'] = (peerStats['added'] ?? 0) + 1;
            }
          }
        }
        if (event.containsKey('PeerConnRemoved')) {
          final payload = event['PeerConnRemoved'];
          if (payload is Map<String, dynamic>) {
            final peerId = (payload['peer_id'] as num?)?.toInt();
            if (peerId != null) {
              final peerStats = stats.putIfAbsent(
                peerId,
                () => <String, int>{'added': 0, 'removed': 0},
              );
              peerStats['removed'] = (peerStats['removed'] ?? 0) + 1;
            }
          }
        }
      } catch (_) {}
    }

    return stats;
  }

  static bool _isRouteRemoteReachable(
    Map<String, dynamic> routeMap,
    String? ipv4,
  ) {
    if (ipv4 == null || ipv4.isEmpty || ipv4 == '未分配 IP') {
      return false;
    }
    final latency = routeMap['path_latency'];
    if (latency is num && latency < 0) {
      return false;
    }
    return true;
  }

  static String _describePeerMode(
    Map<String, dynamic> peerMap,
    Map<String, dynamic> routeMap,
    Map<int, Map<String, dynamic>> routeByPeerId,
  ) {
    final cost = (routeMap['cost'] as num?)?.toInt() ?? 0;
    final peerId = (routeMap['peer_id'] as num?)?.toInt() ?? 0;
    final nextHopPeerId = (routeMap['next_hop_peer_id'] as num?)?.toInt() ?? 0;
    final directlyConnected =
        (peerMap['directly_connected_conns'] as List?)?.isNotEmpty ?? false;

    if (cost <= 1 && directlyConnected) {
      return '直连 (LAN)';
    }
    if (cost <= 1) {
      return 'P2P 直连';
    }

    final nextHopRoute = routeByPeerId[nextHopPeerId];
    final nextHopName = (nextHopRoute?['hostname'] as String?)?.trim();
    if (nextHopPeerId != 0 && nextHopPeerId != peerId) {
      if (nextHopRoute?['feature_flag'] is Map &&
          nextHopRoute?['feature_flag']['is_public_server'] == true) {
        return '经公共中继';
      }
      if (nextHopName != null && nextHopName.isNotEmpty) {
        return '经 $nextHopName 中继';
      }
    }

    return '中继';
  }

  static String _describeRouteMode(
    Map<String, dynamic> routeMap,
    Map<int, Map<String, dynamic>> routeByPeerId,
  ) {
    final cost = (routeMap['cost'] as num?)?.toInt() ?? 0;
    final peerId = (routeMap['peer_id'] as num?)?.toInt() ?? 0;
    final nextHopPeerId = (routeMap['next_hop_peer_id'] as num?)?.toInt() ?? 0;
    if (cost <= 1) {
      return '直连';
    }
    final nextHopRoute = routeByPeerId[nextHopPeerId];
    if (nextHopRoute?['feature_flag'] is Map &&
        nextHopRoute?['feature_flag']['is_public_server'] == true) {
      return '经公共中继';
    }
    final nextHopName = (nextHopRoute?['hostname'] as String?)?.trim();
    if (nextHopPeerId != 0 &&
        nextHopPeerId != peerId &&
        nextHopName != null &&
        nextHopName.isNotEmpty) {
      return '经 $nextHopName 中继';
    }
    return '中继';
  }

  static String _describePeerHealth(Map<String, int>? stats) {
    if (stats == null) {
      return '稳定';
    }
    final removed = stats['removed'] ?? 0;
    final added = stats['added'] ?? 0;
    if (removed >= 3) {
      return '频繁重连';
    }
    if (removed > 0 && added > 0) {
      return '最近重连';
    }
    return '稳定';
  }
}
