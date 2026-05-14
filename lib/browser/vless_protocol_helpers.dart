import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const String webSocketGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

String buildWebSocketHostHeader({
  required String httpHost,
  required int port,
  required bool useTls,
}) {
  final trimmedHost = httpHost.trim();
  if (trimmedHost.isEmpty) {
    return trimmedHost;
  }

  if (hasExplicitPort(trimmedHost)) {
    return trimmedHost;
  }

  final defaultPort = useTls ? 443 : 80;
  if (port == defaultPort) {
    return trimmedHost;
  }

  if (trimmedHost.contains(':') &&
      !(trimmedHost.startsWith('[') && trimmedHost.endsWith(']'))) {
    return '[$trimmedHost]:$port';
  }

  return '$trimmedHost:$port';
}

bool hasExplicitPort(String host) {
  final closingBracket = host.lastIndexOf(']');
  if (host.startsWith('[') && closingBracket != -1) {
    return closingBracket < host.length - 1 && host[closingBracket + 1] == ':';
  }

  return ':'.allMatches(host).length == 1;
}

String generateWebSocketKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64Encode(bytes);
}

Future<InternetAddress> resolvePreferredAddress(String host) async {
  final addresses = await InternetAddress.lookup(host);
  if (addresses.isEmpty) {
    throw SocketException('Failed to resolve $host');
  }

  return selectPreferredAddress(addresses);
}

List<InternetAddress> orderPreferredAddresses(List<InternetAddress> addresses) {
  final ipv4 = <InternetAddress>[];
  final others = <InternetAddress>[];
  for (final address in addresses) {
    if (address.type == InternetAddressType.IPv4) {
      ipv4.add(address);
    } else {
      others.add(address);
    }
  }
  return [...ipv4, ...others];
}

Future<Socket> connectSocketWithFallback(
  List<InternetAddress> addresses,
  int port,
) async {
  Object? lastError;
  StackTrace? lastStackTrace;

  for (final address in orderPreferredAddresses(addresses)) {
    try {
      return await Socket.connect(address, port);
    } catch (error, stackTrace) {
      lastError = error;
      lastStackTrace = stackTrace;
    }
  }

  if (lastError != null && lastStackTrace != null) {
    Error.throwWithStackTrace(lastError, lastStackTrace);
  }

  throw SocketException(
    'Failed to connect to any resolved address on port $port',
  );
}

InternetAddress selectPreferredAddress(List<InternetAddress> addresses) {
  for (final address in addresses) {
    if (address.type == InternetAddressType.IPv4) {
      return address;
    }
  }

  return addresses.first;
}

class VlessResponseConsumeResult {
  const VlessResponseConsumeResult({
    required this.headerPending,
    required this.payload,
  });

  final bool headerPending;
  final Uint8List? payload;
}

VlessResponseConsumeResult consumeVlessResponseHeader({
  required bool pending,
  required BytesBuilder buffered,
  required List<int> chunk,
}) {
  if (!pending) {
    return VlessResponseConsumeResult(
      headerPending: false,
      payload: Uint8List.fromList(chunk),
    );
  }

  buffered.add(chunk);
  final bytes = buffered.takeBytes();
  if (bytes.length < 2) {
    buffered.add(bytes);
    return const VlessResponseConsumeResult(headerPending: true, payload: null);
  }

  final addonsLength = bytes[1];
  final headerLength = 2 + addonsLength;
  if (bytes.length < headerLength) {
    buffered.add(bytes);
    return const VlessResponseConsumeResult(headerPending: true, payload: null);
  }

  final payload = bytes.sublist(headerLength);
  return VlessResponseConsumeResult(
    headerPending: false,
    payload: payload.isEmpty ? Uint8List(0) : Uint8List.fromList(payload),
  );
}

Uint8List buildVlessRequest(String uuid, String targetHost, int targetPort) {
  final builder = BytesBuilder();

  builder.addByte(0x00);
  builder.add(uuidToBytes(uuid));
  builder.addByte(0x00);
  builder.addByte(0x01);
  builder.add([(targetPort >> 8) & 0xff, targetPort & 0xff]);

  final addressType = vlessAddressType(targetHost);
  builder.addByte(addressType);

  switch (addressType) {
    case 0x01:
    case 0x03:
      builder.add(InternetAddress(targetHost).rawAddress);
      break;
    case 0x02:
      final hostBytes = utf8.encode(targetHost);
      if (hostBytes.length > 255) {
        throw ArgumentError.value(
          targetHost,
          'targetHost',
          'Domain is too long',
        );
      }
      builder.addByte(hostBytes.length);
      builder.add(hostBytes);
      break;
    default:
      throw ArgumentError.value(targetHost, 'targetHost', 'Unsupported host');
  }

  return builder.toBytes();
}

Uint8List uuidToBytes(String uuid) {
  final normalized = uuid.toLowerCase().replaceAll('-', '');
  if (normalized.length != 32) {
    throw FormatException('Invalid UUID: $uuid');
  }
  final bytes = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    bytes[i] = int.parse(normalized.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

int vlessAddressType(String host) {
  final address = InternetAddress.tryParse(host);
  if (address == null) {
    return 0x02;
  }
  if (address.type == InternetAddressType.IPv4) {
    return 0x01;
  }
  if (address.type == InternetAddressType.IPv6) {
    return 0x03;
  }
  return 0x02;
}

int indexOfHttpHeaderTerminator(List<int> bytes) {
  for (var index = 0; index <= bytes.length - 4; index++) {
    if (bytes[index] == 13 &&
        bytes[index + 1] == 10 &&
        bytes[index + 2] == 13 &&
        bytes[index + 3] == 10) {
      return index + 4;
    }
  }
  return -1;
}

Uint8List randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}
