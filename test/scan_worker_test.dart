import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/scan/scan_worker.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lumen_worker');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('turns files into index rows, with a fallback date', () async {
    final file = File('${dir.path}/IMG_20240115_183022.jpg');
    await file.writeAsBytes(List<int>.generate(64, (i) => i));

    final rows = await readCandidates(<PendingFile>[
      PendingFile.of(
        file.path,
        sizeBytes: 64,
        modifiedMs: DateTime(2020, 6, 1).millisecondsSinceEpoch,
      ),
    ]);

    expect(rows, hasLength(1));
    expect(rows.single.fileName, 'IMG_20240115_183022.jpg');
    expect(rows.single.ext, 'jpg');
    expect(rows.single.folder, dir.path);
    expect(rows.single.sizeBytes, 64);
    // Junk bytes carry no EXIF, so the name wins over the mtime.
    final taken = DateTime.fromMillisecondsSinceEpoch(rows.single.takenAtMs);
    expect(taken.year, 2024);
    expect(taken.month, 1);
    expect(taken.day, 15);
  });

  test('falls back to the file time when the name has no date', () async {
    final file = File('${dir.path}/beach.jpg');
    await file.writeAsBytes(List<int>.generate(16, (i) => i));
    final mtime = DateTime(2021, 3, 4, 5, 6).millisecondsSinceEpoch;

    final rows = await readCandidates(<PendingFile>[
      PendingFile.of(file.path, sizeBytes: 16, modifiedMs: mtime),
    ]);

    expect(rows.single.takenAtMs, mtime);
  });

  test('a missing file still produces a row rather than throwing', () async {
    final rows = await readCandidates(<PendingFile>[
      PendingFile.of('${dir.path}/gone.jpg', sizeBytes: 1, modifiedMs: 1),
    ]);

    expect(rows, hasLength(1));
    expect(rows.single.takenAtMs, 1);
  });
}
