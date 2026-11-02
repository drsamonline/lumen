import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Perceptual hashing for duplicate detection.
///
/// A dHash compares neighbouring pixels across an 8x8 grid, so it survives
/// re-encoding, resizing and mild recompression — exactly the ways a duplicate
/// arrives in a real library (a WhatsApp copy, a "IMG_0001 (1).jpg" re-save).
///
/// The grid is sampled from the **centre square** of the image, which makes the
/// hash independent of aspect ratio: a 3:2 original and a 1:1 crop of the same
/// scene still hash close together, and two photos with different shapes always
/// produce the same number of bits.
class HashService {
  /// The hash is computed from the 480 px thumbnail that already exists on
  /// disk, so finding duplicates costs one decode per photo and reuses work the
  /// grid already paid for.
  static const int _decodeWidth = 32;

  static Future<int?> hashThumbnailFile(String thumbPath) async {
    try {
      final bytes = await File(thumbPath).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _decodeWidth,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final hash = await dHash(image);
      image.dispose();
      codec.dispose();
      return hash;
    } catch (_) {
      return null;
    }
  }

  /// Returns a 64-bit hash packed into a Dart int. The value may be negative;
  /// that is fine, it is only ever compared with [hamming], never ordered.
  static Future<int?> dHash(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final rgba = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return dHashFromRgba(rgba, image.width, image.height);
  }

  static int? dHashFromRgba(Uint8List rgba, int width, int height) {
    if (width < 2 || height < 2) return null;
    final side = math.min(width, height);
    final originX = (width - side) ~/ 2;
    final originY = (height - side) ~/ 2;

    double luminanceAt(int gx, int gy) {
      final x = originX + (gx * (side - 1) / 8).round();
      final y = originY + (gy * (side - 1) / 7).round();
      final i = (y * width + x) * 4;
      if (i + 2 >= rgba.length) return 0;
      return 0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2];
    }

    var bits = 0;
    for (var gy = 0; gy < 8; gy++) {
      for (var gx = 0; gx < 8; gx++) {
        final left = luminanceAt(gx, gy);
        final right = luminanceAt(gx + 1, gy);
        bits = (bits << 1) | (left < right ? 1 : 0);
      }
    }
    return bits;
  }

  /// Number of differing bits between two hashes.
  static int hamming(int a, int b) {
    var x = a ^ b;
    var count = 0;
    // Unsigned shift so a negative int (a hash with the top bit set) still
    // terminates instead of looping forever on the sign bit.
    while (x != 0) {
      count += x & 1;
      x = x >>> 1;
    }
    return count;
  }

  /// Four 16-bit bands. Two photos that share a band are candidates, which
  /// turns the all-pairs comparison into a handful of bucket lookups.
  static List<int> bands(int hash, {int count = 4}) {
    return <int>[
      for (var i = 0; i < count; i++) (hash >>> (i * 16)) & 0xFFFF,
    ];
  }
}
