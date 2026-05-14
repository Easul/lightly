import 'dart:convert';
import 'dart:typed_data';

import 'proxy_buffered_stream_reader.dart';

class HttpHeaderReader {
  HttpHeaderReader(this._reader);

  final BufferedStreamReader _reader;

  Future<String?> readLine() async {
    final buffer = <int>[];
    while (true) {
      final byte = await _reader.readByte();
      buffer.add(byte);
      if (buffer.length >= 2 &&
          buffer[buffer.length - 2] == 0x0d &&
          buffer[buffer.length - 1] == 0x0a) {
        final line = utf8.decode(buffer.sublist(0, buffer.length - 2));
        return line;
      }
    }
  }

  Future<Map<String, String>> readHeaders() async {
    final headers = <String, String>{};
    while (true) {
      final line = await readLine();
      if (line == null || line.isEmpty) {
        break;
      }
      final colonIndex = line.indexOf(':');
      if (colonIndex > 0) {
        final key = line.substring(0, colonIndex).trim().toLowerCase();
        final value = line.substring(colonIndex + 1).trim();
        headers[key] = value;
      }
    }
    return headers;
  }

  Uint8List takeRemaining() {
    return _reader.takeBuffered();
  }

  Future<void> close() async {}
}
