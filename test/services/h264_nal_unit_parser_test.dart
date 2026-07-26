import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/remote_control/domain/h264_nal_unit_parser.dart';

void main() {
  test('extracts SPS and PPS from the existing Annex B stream format', () {
    final units = H264NalUnitParser.parse(
      Uint8List.fromList(<int>[
        0,
        0,
        0,
        1,
        0x67,
        0x11,
        0,
        0,
        1,
        0x68,
        0x22,
        0,
        0,
        0,
        1,
        0x65,
        0x33,
        0x44,
        0x55,
      ]),
    );

    expect(H264NalUnitParser.typeOf(units[0]), 7);
    expect(H264NalUnitParser.typeOf(units[1]), 8);
  });

  test('returns minus one for an empty NAL unit', () {
    expect(H264NalUnitParser.typeOf(Uint8List(0)), -1);
  });
}
