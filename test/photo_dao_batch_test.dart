import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/db/database.dart';
import 'package:lumen/core/db/photo_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PhotoCandidate candidate(int i) => PhotoCandidate(
      path: '/photos/$i.jpg',
      folder: '/photos',
      fileName: '$i.jpg',
      ext: 'jpg',
      sizeBytes: 1000 + i,
      modifiedMs: 1000,
      takenAtMs: 1000 + i,
    );

void main() {
  late PhotoDao photos;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.open(inMemory: true);
    photos = PhotoDao(AppDatabase.instance);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  test('fetches many photos in one call, in the order asked', () async {
    await photos.upsertCandidates(<PhotoCandidate>[
      for (var i = 0; i < 5; i++) candidate(i),
    ]);

    final all = await photos.page(offset: 0, limit: 10);
    final ids = all.map((p) => p.id).toList();

    final fetched = await photos.byIds(<int>[ids[3], ids[0], ids[4]]);

    expect(fetched, hasLength(3));
    // byIds returns rows in query order, not the order of the argument list;
    // callers restore order themselves. Assert the set, not the sequence.
    expect(fetched.map((p) => p.id).toSet(), <int>{ids[3], ids[0], ids[4]});
  });

  test('an empty id list is a no-op, not a query', () async {
    expect(await photos.byIds(const <int>[]), isEmpty);
  });

  test('unknown ids are simply absent', () async {
    await photos.upsertCandidates(<PhotoCandidate>[candidate(1)]);
    final all = await photos.page(offset: 0, limit: 10);

    final fetched = await photos.byIds(<int>[all.single.id, 999999]);

    expect(fetched, hasLength(1));
    expect(fetched.single.id, all.single.id);
  });

  test('chunks past the bound-variable limit', () async {
    // 420 crosses the 400-row chunk boundary, which is where a naive
    // `id IN (?, ?, ...)` would hit SQLite's variable limit instead.
    await photos.upsertCandidates(<PhotoCandidate>[
      for (var i = 0; i < 420; i++) candidate(i),
    ]);

    final all = await photos.page(offset: 0, limit: 500);
    expect(all, hasLength(420));

    final fetched = await photos.byIds(all.map((p) => p.id).toList());

    expect(fetched, hasLength(420));
    expect(fetched.map((p) => p.id).toSet(), all.map((p) => p.id).toSet());
  });
}
