import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/scan/hash_service.dart';

/// Builds an RGBA buffer where luminance rises left-to-right on a gradient.
Uint8List gradient(int width, int height, {bool reverse = false}) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final t = reverse ? (width - 1 - x) : x;
      final value = (t * 255 ~/ (width - 1)).clamp(0, 255);
      final i = (y * width + x) * 4;
      bytes[i] = value;
      bytes[i + 1] = value;
      bytes[i + 2] = value;
      bytes[i + 3] = 255;
    }
  }
  return bytes;
}

void main() {
  group('dHash', () {
    test('is stable for the same pixels', () {
      final a = HashService.dHashFromRgba(gradient(32, 32), 32, 32);
      final b = HashService.dHashFromRgba(gradient(32, 32), 32, 32);
      expect(a, isNotNull);
      expect(a, equals(b));
    });

    test('a mirrored image hashes to the complement', () {
      final forward = HashService.dHashFromRgba(gradient(32, 32), 32, 32)!;
      final reverse = HashService.dHashFromRgba(gradient(32, 32, reverse: true), 32, 32)!;
      // Every one of the 64 comparisons flips, so the hashes differ in 64 bits.
      expect(HashService.hamming(forward, reverse), 64);
    });

    test('a flat image produces a constant hash', () {
      final flat = Uint8List(32 * 32 * 4);
      for (var i = 0; i < flat.length; i += 4) {
        flat[i] = 128;
        flat[i + 1] = 128;
        flat[i + 2] = 128;
        flat[i + 3] = 255;
      }
      final h1 = HashService.dHashFromRgba(flat, 32, 32)!;
      // No neighbour is brighter, so no bit is set.
      expect(h1, 0);
    });

    test('refuses degenerate input', () {
      expect(HashService.dHashFromRgba(Uint8List(16), 1, 1), isNull);
    });

    test('is aspect-ratio independent', () {
      // The same gradient at 3:2 and 1:1 should land close together, because
      // the hash samples the centre square.
      final wide = HashService.dHashFromRgba(gradient(48, 32), 48, 32)!;
      final square = HashService.dHashFromRgba(gradient(32, 32), 32, 32)!;
      expect(HashService.hamming(wide, square), lessThanOrEqualTo(8));
    });
  });

  group('hamming', () {
    test('counts differing bits', () {
      expect(HashService.hamming(0, 0), 0);
      expect(HashService.hamming(0, 1), 1);
      expect(HashService.hamming(0, 0xFF), 8);
      expect(HashService.hamming(0xAAAAAAAA, 0x55555555), 32);
    });

    test('terminates on the sign bit', () {
      // -1 is all 64 bits set; this used to be the classic infinite loop.
      expect(HashService.hamming(-1, 0), 64);
      expect(HashService.hamming(-1, -1), 0);
    });
  });

  group('bands', () {
    test('splits into four 16-bit chunks', () {
      const hash = 0x1234567890ABCDEF;
      final bands = HashService.bands(hash);
      expect(bands.length, 4);
      expect(bands[0], 0xCDEF);
      expect(bands[1], 0x90AB);
      expect(bands[2], 0x5678);
      expect(bands[3], 0x1234);
    });
  });
}
