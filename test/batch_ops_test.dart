import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/db/database.dart';
import 'package:lumen/core/db/photo_dao.dart';
import 'package:lumen/core/models/photo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PhotoCandidate candidate(String name, {int sizeBytes = 1024}) => PhotoCandidate(
      path: '/photos/$name',
      folder: '/photos',
      fileName: name,
      ext: 'jpg',
      sizeBytes: sizeBytes,
      modifiedMs: 1000,
      takenAtMs: 1000,
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

  group('bulk rating and favourites', () {
    test('rates a whole selection in one call', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        candidate('a.jpg'),
        candidate('b.jpg'),
        candidate('c.jpg'),
      ]);
      final ids = (await photos.page(offset: 0, limit: 10)).map((p) => p.id).toList();

      await photos.setRatingMany(ids, 4);

      final rated = await photos.page(
        offset: 0,
        limit: 10,
        filter: const PhotoFilter(minRating: 4),
      );
      expect(rated.length, 3);
    });

    test('only touches the ids given', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        candidate('a.jpg'),
        candidate('b.jpg'),
      ]);
      final all = await photos.page(offset: 0, limit: 10);
      await photos.setRatingMany(<int>[all.first.id], 5);

      final rated = await photos.page(
        offset: 0,
        limit: 10,
        filter: const PhotoFilter(minRating: 1),
      );
      expect(rated.length, 1);
      expect(rated.first.id, all.first.id);
    });

    test('favourites a selection', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        candidate('a.jpg'),
        candidate('b.jpg'),
        candidate('c.jpg'),
      ]);
      final ids = (await photos.page(offset: 0, limit: 10)).map((p) => p.id).toList();
      await photos.setFavoriteMany(ids.take(2).toList(), true);

      final favourites = await photos.page(
        offset: 0,
        limit: 10,
        filter: const PhotoFilter(favoritesOnly: true),
      );
      expect(favourites.length, 2);

      // And it can be undone.
      await photos.setFavoriteMany(ids, false);
      final after = await photos.page(
        offset: 0,
        limit: 10,
        filter: const PhotoFilter(favoritesOnly: true),
      );
      expect(after, isEmpty);
    });

    test('clamps an out-of-range rating', () async {
      await photos.upsertCandidates(<PhotoCandidate>[candidate('a.jpg')]);
      final id = (await photos.page(offset: 0, limit: 1)).first.id;
      await photos.setRatingMany(<int>[id], 99);
      expect((await photos.byId(id))!.rating, 5);
    });

    test('an empty selection is a no-op', () async {
      await photos.upsertCandidates(<PhotoCandidate>[candidate('a.jpg')]);
      await photos.setRatingMany(const <int>[], 3);
      await photos.setFavoriteMany(const <int>[], true);
      expect(await photos.totalBytes(const <int>[]), 0);
      expect((await photos.page(offset: 0, limit: 1)).first.rating, 0);
    });
  });

  group('totalBytes', () {
    test('sums the selection', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        candidate('a.jpg', sizeBytes: 1000),
        candidate('b.jpg', sizeBytes: 2500),
        candidate('c.jpg', sizeBytes: 500),
      ]);
      final all = await photos.page(offset: 0, limit: 10);
      final ids = all.take(2).map((p) => p.id).toList();
      expect(await photos.totalBytes(ids), 3500);
    });
  });
}
