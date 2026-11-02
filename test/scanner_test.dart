import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/db/database.dart';
import 'package:lumen/core/db/photo_dao.dart';
import 'package:lumen/core/scan/scanner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory root;
  late PhotoDao photos;
  late LibraryScanner scanner;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.open(inMemory: true);
    photos = PhotoDao(AppDatabase.instance);
    scanner = LibraryScanner(photos, AppDatabase.instance);
    root = await Directory.systemTemp.createTemp('lumen_scan_test');
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> touch(String relativePath) async {
    final file = File('${root.path}/$relativePath');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(<int>[1, 2, 3, 4]);
  }

  group('scanning', () {
    test('indexes image files and ignores everything else', () async {
      await touch('keep.jpg');
      await touch('also-keep.PNG');
      await touch('notes.txt');
      await touch('video.mp4');

      await scanner.scanRoots(<String>[root.path]);

      final names = (await photos.page(offset: 0, limit: 50))
          .map((p) => p.fileName)
          .toSet();
      expect(names, containsAll(<String>['keep.jpg', 'also-keep.PNG']));
      expect(names, isNot(contains('notes.txt')));
      expect(names, isNot(contains('video.mp4')));
    });

    test('does not descend into skipped directories', () async {
      await touch('keep.jpg');
      await touch('node_modules/vendored.jpg');
      await touch('.cache/thumb.jpg');
      await touch('.git/objects/blob.jpg');

      await scanner.scanRoots(<String>[root.path]);

      final names = (await photos.page(offset: 0, limit: 50))
          .map((p) => p.fileName)
          .toSet();
      expect(names, contains('keep.jpg'));
      expect(names, isNot(contains('vendored.jpg')));
      expect(names, isNot(contains('thumb.jpg')));
      expect(names, isNot(contains('blob.jpg')));
    });

    test('a second scan of unchanged files adds nothing', () async {
      await touch('a.jpg');
      await touch('b.jpg');

      await scanner.scanRoots(<String>[root.path]);
      expect(await photos.count(), 2);

      await scanner.scanRoots(<String>[root.path]);
      expect(await photos.count(), 2);
    });

    test('a file that disappears is marked missing, not deleted', () async {
      await touch('gone.jpg');
      await scanner.scanRoots(<String>[root.path]);
      expect(await photos.count(), 1);

      await File('${root.path}/gone.jpg').delete();
      final progress = await scanner.scanRoots(<String>[root.path]);

      expect(progress.removed, 1);
      // Hidden from the grid, but the row survives so ratings and edits are
      // not lost when a drive is temporarily unmounted.
      expect(await photos.count(), 0);
      final raw = await AppDatabase.instance.db.query('photos');
      expect(raw.length, 1);
    });

    test('an unmounted root does not empty the library', () async {
      await touch('a.jpg');
      await scanner.scanRoots(<String>[root.path]);
      expect(await photos.count(), 1);

      // The folder is gone entirely - a drive unplugged, not an empty library.
      final missingRoot = '${root.path}-does-not-exist';
      final progress = await scanner.scanRoots(<String>[missingRoot]);

      expect(progress.removed, 0);
      expect(await photos.count(), 1, reason: 'nothing may be marked missing');
    });

    test('an empty root is harmless', () async {
      final progress = await scanner.scanRoots(<String>[root.path]);
      expect(progress.error, isNull);
      expect(await photos.count(), 0);
    });
  });
}
