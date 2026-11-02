import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/export/zip_writer.dart';

void main() {
  group('Crc32', () {
    test('matches the published check value', () {
      // The canonical CRC-32 check: "123456789" -> 0xCBF43926.
      final bytes = '123456789'.codeUnits;
      expect(Crc32.compute(bytes), 0xCBF43926);
    });

    test('empty input is zero', () {
      expect(Crc32.compute(<int>[]), 0);
    });
  });

  group('ZipArchiveWriter', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('lumen_zip_test');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('writes a well-formed archive', () async {
      final target = File('${temp.path}/out.zip');
      final size = await ZipArchiveWriter.write(target, <ZipSource>[
        ZipSource.bytes('a.txt', 'hello'.codeUnits),
        ZipSource.bytes('nested/b.txt', 'world'.codeUnits),
      ]);

      expect(size, greaterThan(0));
      final bytes = await target.readAsBytes();
      expect(bytes.length, size);

      // Local file header signature at the start.
      expect(bytes.sublist(0, 4), <int>[0x50, 0x4B, 0x03, 0x04]);
      // End-of-central-directory signature at the end.
      expect(
        bytes.sublist(bytes.length - 22, bytes.length - 18),
        <int>[0x50, 0x4B, 0x05, 0x06],
      );

      // Two entries recorded in the EOCD.
      final eocd = bytes.length - 22;
      final entryCount = bytes[eocd + 10] | (bytes[eocd + 11] << 8);
      expect(entryCount, 2);

      // The payloads are stored uncompressed, so they appear verbatim.
      expect(String.fromCharCodes(bytes).contains('hello'), isTrue);
      expect(String.fromCharCodes(bytes).contains('world'), isTrue);
    });

    test('round-trips through the system unzip', () async {
      final target = File('${temp.path}/real.zip');
      await ZipArchiveWriter.write(target, <ZipSource>[
        ZipSource.bytes('one.txt', 'first file'.codeUnits),
        ZipSource.bytes('dir/two.txt', 'second file'.codeUnits),
      ]);

      final result = await Process.run(
        'unzip',
        <String>['-t', target.path],
        stdoutEncoding: null,
      );
      // `unzip` is not present on every CI image; only assert when it is.
      if (result.exitCode != 0 && result.stderr.toString().contains('not found')) {
        return;
      }
      expect(result.exitCode, 0, reason: result.stdout.toString());
    });
  });
}
