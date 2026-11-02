import 'package:path/path.dart' as p;

/// A capture date recovered from a file name.
///
/// Most phone and camera files carry one — `IMG_20240115_183022`,
/// `PXL_20240115_183022123`, `Screenshot_20240115-183022` — and it is far closer
/// to the truth than the file's mtime, which on Android is the date the file was
/// *copied*. Without this fallback a phone library collapses into whichever
/// month it was migrated, which is exactly what the month headers showed.
class CaptureDate {
  /// Matches `YYYYMMDD` anywhere in the stem, guarded to plausible years.
  static final RegExp _stamp = RegExp(r'(19|20)\d{2}[0-1]\d[0-3]\d');
  static final RegExp _separator = RegExp(r'^[-_ T]');
  static final RegExp _time = RegExp(r'^(\d{2})(\d{2})(\d{2})');

  /// Null when the name carries nothing usable, or carries a date in the future
  /// — which is a filename artefact, not a capture.
  static int? fromFileName(String path) {
    final stem = p.basenameWithoutExtension(path);
    final match = _stamp.firstMatch(stem);
    if (match == null) return null;

    final digits = match.group(0)!;
    final year = int.parse(digits.substring(0, 4));
    final month = int.parse(digits.substring(4, 6));
    final day = int.parse(digits.substring(6, 8));
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    // Time of day when the name has one right after the date; midday otherwise,
    // so a photo lands in the right day even in a negative-offset timezone.
    final rest = stem.substring(match.end).replaceFirst(_separator, '');
    final clock = _time.firstMatch(rest);
    final hour = clock == null ? 12 : int.parse(clock.group(1)!);
    final minute = clock == null ? 0 : int.parse(clock.group(2)!);
    final second = clock == null ? 0 : int.parse(clock.group(3)!);

    final date = DateTime(
      year,
      month,
      day,
      hour.clamp(0, 23),
      minute.clamp(0, 59),
      second.clamp(0, 59),
    );
    if (date.isAfter(DateTime.now())) return null;
    return date.millisecondsSinceEpoch;
  }
}
