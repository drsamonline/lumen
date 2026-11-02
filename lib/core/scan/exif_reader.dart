import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';

/// The subset of EXIF Lumen cares about. Everything is nullable: a screenshot
/// has no camera, a scanned photo has no GPS, and that is fine.
class ExifData {
  const ExifData({
    this.takenAtMs,
    this.width,
    this.height,
    this.make,
    this.model,
    this.iso,
    this.fNumber,
    this.exposureTime,
    this.focalLength,
    this.lat,
    this.lon,
    this.orientation = 1,
  });

  final int? takenAtMs;
  final int? width;
  final int? height;
  final String? make;
  final String? model;
  final int? iso;
  final double? fNumber;
  final String? exposureTime;
  final double? focalLength;
  final double? lat;
  final double? lon;
  final int orientation;
}

class ExifReader {
  /// EXIF lives at the head of the file. The APP1 segment is normally inside
  /// the first 64 KB, and 256 KB is generous even for a file carrying large
  /// XMP. It used to be 512 KB, which is 25 GB of reads across a 50,000-photo
  /// first scan for metadata that is not there.
  ///
  /// Anything past this window is a file we fall back on the file name for,
  /// which is what the fallback chain is for.
  /// camera JPEG/HEIC without paying for a full-file read.
  static const int _headBytes = 256 * 1024;

  static Future<ExifData> read(String path) async {
    try {
      final file = File(path);
      final length = await file.length();
      final readLength = length < _headBytes ? length : _headBytes;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.openRead(0, readLength)) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      final tags = await readExifFromBytes(bytes);
      if (tags.isEmpty) return const ExifData();
      return ExifData(
        takenAtMs: _parseExifDate(_str(tags, const <String>[
          'EXIF DateTimeOriginal',
          'EXIF DateTimeDigitized',
          'Image DateTime',
        ])),
        width: _asInt(_str(tags, const <String>[
          'EXIF PixelXDimension',
          'EXIF ImageWidth',
          'Image ImageWidth',
        ])),
        height: _asInt(_str(tags, const <String>[
          'EXIF PixelYDimension',
          'EXIF ImageLength',
          'Image ImageLength',
        ])),
        make: _clean(_str(tags, const <String>['Image Make', 'EXIF Make'])),
        model: _clean(_str(tags, const <String>['Image Model', 'EXIF Model'])),
        iso: _asInt(_str(tags, const <String>[
          'EXIF ISOSpeedRatings',
          'EXIF PhotographicSensitivity',
        ])),
        fNumber: _rational(_str(tags, const <String>['EXIF FNumber', 'EXIF ApertureValue'])),
        exposureTime: _clean(_str(tags, const <String>['EXIF ExposureTime', 'EXIF ShutterSpeedValue'])),
        focalLength: _rational(_str(tags, const <String>['EXIF FocalLength'])),
        lat: _gps(
          _str(tags, const <String>['EXIF GPS GPSLatitude']),
          _clean(_str(tags, const <String>['EXIF GPS GPSLatitudeRef'])),
        ),
        lon: _gps(
          _str(tags, const <String>['EXIF GPS GPSLongitude']),
          _clean(_str(tags, const <String>['EXIF GPS GPSLongitudeRef'])),
        ),
        orientation: _asInt(_str(tags, const <String>['Image Orientation'])) ?? 1,
      );
    } catch (_) {
      // A corrupt or exotic file must never break a scan.
      return const ExifData();
    }
  }

  static String? _str(Map<String, IfdTag> tags, List<String> keys) {
    for (final key in keys) {
      final tag = tags[key];
      if (tag == null) continue;
      final value = tag.printable.trim();
      if (value.isEmpty) continue;
      if (value == 'N/A') continue;
      return value;
    }
    return null;
  }

  static String? _clean(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  static int? _asInt(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'-?\d+').firstMatch(raw);
    if (match == null) return null;
    return int.tryParse(match.group(0)!);
  }

  /// EXIF rationals arrive as "28/10", "1/250" or occasionally "2.8".
  static double? _rational(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.trim();
    final slash = RegExp(r'^(-?\d+(?:\.\d+)?)\s*/\s*(-?\d+(?:\.\d+)?)$').firstMatch(cleaned);
    if (slash != null) {
      final num_ = double.tryParse(slash.group(1)!);
      final den = double.tryParse(slash.group(2)!);
      if (num_ == null || den == null || den == 0) return null;
      return num_ / den;
    }
    final plain = double.tryParse(cleaned);
    if (plain != null) return plain;
    final digits = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(cleaned);
    if (digits == null) return null;
    return double.tryParse(digits.group(0)!);
  }

  /// GPS coordinates arrive as three rationals (deg, min, sec) plus a
  /// hemisphere letter. Anything unparseable returns null rather than 0,0 —
  /// which would otherwise drop a photo in the Gulf of Guinea.
  static double? _gps(String? raw, String? ref) {
    if (raw == null) return null;
    final parts = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length < 3) return null;
    var degrees = 0.0;
    for (var i = 0; i < 3; i++) {
      final value = _rational(parts[i]);
      if (value == null) return null;
      degrees += value / (i == 0 ? 1 : (i == 1 ? 60 : 3600));
    }
    if (degrees.abs() < 0.0001) return null;
    final upper = (ref ?? '').toUpperCase();
    if (upper.startsWith('S') || upper.startsWith('W')) degrees = -degrees;
    return degrees;
  }

  /// "2024:03:15 14:22:01" — note the colons in the date, a famous EXIF quirk.
  static int? _parseExifDate(String? raw) {
    if (raw == null) return null;
    final match = RegExp(
      r'(\d{4})[:\-](\d{2})[:\-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(raw);
    if (match == null) return null;
    try {
      final dt = DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
      if (dt.year < 1900) return null;
      return dt.millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }
}
