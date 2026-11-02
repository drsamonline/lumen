import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/scan/capture_date.dart';

void main() {
  DateTime of(int? ms) => DateTime.fromMillisecondsSinceEpoch(ms!);

  group('reads the stamp out of a file name', () {
    test('camera style, with time', () {
      final date = of(CaptureDate.fromFileName('/x/IMG_20240115_183022.jpg'));
      expect(date.year, 2024);
      expect(date.month, 1);
      expect(date.day, 15);
      expect(date.hour, 18);
      expect(date.minute, 30);
    });

    test('screenshot style, dash separator', () {
      final date = of(CaptureDate.fromFileName('Screenshot_20231102-091500.png'));
      expect(date.year, 2023);
      expect(date.month, 11);
      expect(date.hour, 9);
    });

    test('date with no time lands at midday', () {
      final date = of(CaptureDate.fromFileName('holiday-20220704.jpg'));
      expect(date.day, 4);
      expect(date.hour, 12, reason: 'midday keeps the day right in any timezone');
    });

    test('pixel style with trailing milliseconds', () {
      final date = of(CaptureDate.fromFileName('PXL_20240115_183022123.jpg'));
      expect(date.year, 2024);
      expect(date.hour, 18);
    });
  });

  group('refuses what it cannot trust', () {
    test('no date in the name', () {
      expect(CaptureDate.fromFileName('beach-sunset.jpg'), isNull);
      expect(CaptureDate.fromFileName('DSC_0001.JPG'), isNull);
    });

    test('an impossible month or day', () {
      expect(CaptureDate.fromFileName('IMG_20241345_120000.jpg'), isNull);
      expect(CaptureDate.fromFileName('IMG_20240132_120000.jpg'), isNull);
    });

    test('a date in the future', () {
      expect(CaptureDate.fromFileName('IMG_29990101_120000.jpg'), isNull);
    });

    test('a bare four-digit number is not a date', () {
      expect(CaptureDate.fromFileName('scan-1234.jpg'), isNull);
    });
  });
}
