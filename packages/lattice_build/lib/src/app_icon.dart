import 'dart:io';
import 'dart:typed_data';

/// Writes a placeholder application icon (§7.9).
///
/// Every Linux packaging format insists on an icon, and `flutter create` does
/// not produce one — so without this, packaging fails on a project the user
/// never got the chance to do anything wrong to. A generated placeholder means
/// `lattice package` works the moment a project exists; supplying a real icon
/// stays a thing you do when you have one.
///
/// The motif is the lattice the node canvas is drawn on: a grid of dots, every
/// fifth one brighter.
class AppIcon {
  const AppIcon();

  /// Writes a [size]×[size] PNG to [path] unless a file is already there —
  /// a real icon dropped in by hand is never overwritten.
  Future<bool> writePlaceholder(String path, {int size = 512}) async {
    final file = File(path);
    if (file.existsSync()) return false;
    await file.parent.create(recursive: true);
    await file.writeAsBytes(_render(size));
    return true;
  }

  Uint8List _render(int size) {
    const ground = [0x15, 0x1A, 0x28];
    const minor = [0x2E, 0x35, 0x46];
    const major = [0x6A, 0xA9, 0xF0];

    final step = size ~/ 16;
    final radius = (size / 110).ceil();

    // One filter byte per row, then RGB per pixel.
    final raw = Uint8List(size * (1 + size * 3));
    var offset = 0;
    for (var y = 0; y < size; y++) {
      raw[offset++] = 0;
      for (var x = 0; x < size; x++) {
        var colour = ground;
        final column = (x / step).round();
        final row = (y / step).round();
        final dx = x - column * step;
        final dy = y - row * step;
        if (dx * dx + dy * dy <= radius * radius) {
          colour = (column % 5 == 0 && row % 5 == 0) ? major : minor;
        }
        raw[offset++] = colour[0];
        raw[offset++] = colour[1];
        raw[offset++] = colour[2];
      }
    }

    return _encodePng(size, raw);
  }

  static Uint8List _encodePng(int size, Uint8List raw) {
    final header = BytesBuilder()
      ..add(_int32(size))
      ..add(_int32(size))
      ..add([8, 2, 0, 0, 0]); // 8-bit, truecolour

    return Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      ..._chunk('IHDR', header.toBytes()),
      ..._chunk('IDAT', ZLibEncoder().convert(raw)),
      ..._chunk('IEND', const []),
    ]);
  }

  static List<int> _chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    return [..._int32(data.length), ...body, ..._int32(_crc32(body))];
  }

  static List<int> _int32(int value) => [
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ];

  static final List<int> _crcTable = List<int>.generate(256, (i) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int _crc32(List<int> bytes) {
    var crc = 0xFFFFFFFF;
    for (final byte in bytes) {
      crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }
}
