import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/export/metadata_check.dart';

/// Builds the smallest possible PNG, optionally carrying a tEXt block.
Uint8List pngBytes({required bool withText}) {
  final out = BytesBuilder();
  out.add(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  void chunk(String type, List<int> data) {
    final length = data.length;
    out.add(<int>[
      (length >> 24) & 0xFF,
      (length >> 16) & 0xFF,
      (length >> 8) & 0xFF,
      length & 0xFF,
    ]);
    out.add(type.codeUnits);
    out.add(data);
    out.add(<int>[0, 0, 0, 0]); // CRC is not validated by the scanner
  }

  chunk('IHDR', List<int>.filled(13, 0));
  if (withText) chunk('tEXt', 'Software\x00Lumen'.codeUnits);
  chunk('IEND', <int>[]);
  return out.takeBytes();
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lumen_meta_test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('reports a tEXt block', () async {
    final file = File('${temp.path}/dirty.png');
    await file.writeAsBytes(pngBytes(withText: true));
    final found = await MetadataCheck.scan(file);
    expect(found, contains('tEXt'));
  });

  test('reports nothing for a clean PNG', () async {
    final file = File('${temp.path}/clean.png');
    await file.writeAsBytes(pngBytes(withText: false));
    expect(await MetadataCheck.scan(file), isEmpty);
  });

  test('does not crash on a non-image', () async {
    final file = File('${temp.path}/notes.txt');
    await file.writeAsString('not an image at all');
    final found = await MetadataCheck.scan(file);
    expect(found, isNotEmpty);
  });
}
