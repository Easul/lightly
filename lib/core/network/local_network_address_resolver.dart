import 'dart:io';

bool _isPrivateIpv4Address(String address) {
  if (address.startsWith('10.')) {
    return true;
  }
  if (address.startsWith('192.168.')) {
    return true;
  }
  final match = RegExp(r'^172\.(\d+)\.').firstMatch(address);
  if (match == null) {
    return false;
  }
  final secondOctet = int.tryParse(match.group(1) ?? '');
  return secondOctet != null && secondOctet >= 16 && secondOctet <= 31;
}

Future<List<String>> resolvePrivateNetworkUrls({required int port}) async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
      includeLoopback: false,
    );
    final urls = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final host = address.address;
        if (_isPrivateIpv4Address(host)) {
          urls.add('http://$host:$port');
        }
      }
    }
    final sorted = urls.toList()..sort();
    return sorted;
  } catch (_) {
    return const <String>[];
  }
}
