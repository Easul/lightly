import 'dart:typed_data';

class H264NalUnitParser {
  const H264NalUnitParser._();

  /// Extracts NAL units from the existing raw Annex B screen stream format.
  static List<Uint8List> parse(Uint8List data) {
    final units = <Uint8List>[];
    int i = 0;

    while (i < data.length - 4) {
      if (data[i] == 0 && data[i + 1] == 0) {
        int startCodeLength;
        if (data[i + 2] == 0 && data[i + 3] == 1) {
          startCodeLength = 4;
        } else if (data[i + 2] == 1) {
          startCodeLength = 3;
        } else {
          i++;
          continue;
        }

        int j = i + startCodeLength;
        while (j < data.length - 3) {
          if (data[j] == 0 &&
              data[j + 1] == 0 &&
              (data[j + 2] == 1 ||
                  (data[j + 2] == 0 &&
                      j + 3 < data.length &&
                      data[j + 3] == 1))) {
            break;
          }
          j++;
        }

        units.add(Uint8List.fromList(data.sublist(i + startCodeLength, j)));
        i = j;
      } else {
        i++;
      }
    }

    return units;
  }

  static int typeOf(Uint8List nalUnit) {
    if (nalUnit.isEmpty) return -1;
    return nalUnit[0] & 0x1F;
  }
}
