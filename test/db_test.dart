import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/db/album_dao.dart';
import 'package:lumen/core/db/database.dart';
import 'package:lumen/core/db/edit_dao.dart';
import 'package:lumen/core/db/photo_dao.dart';
import 'package:lumen/core/models/edit_recipe.dart';
import 'package:lumen/core/models/photo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PhotoCandidate candidate(
  String name, {
  String folder = '/photos/2024',
  int takenAtMs = 1700000000000,
  double? lat,
  double? lon,
}) {
  return PhotoCandidate(
    path: '$folder/$name',
    folder: folder,
    fileName: name,
    ext: 'jpg',
    sizeBytes: 1024,
    modifiedMs: takenAtMs,
    takenAtMs: takenAtMs,
    width: 4000,
    height: 3000,
    cameraModel: 'X-T5',
    lat: lat,
    lon: lon,
  );
}

void main() {
  late PhotoDao photos;
  late AlbumDao albums;
  late EditDao edits;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.open(inMemory: true);
    photos = PhotoDao(AppDatabase.instance);
    albums = AlbumDao(AppDatabase.instance);
    edits = EditDao(AppDatabase.instance);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  group('photo index', () {
    test('inserts, counts and pages', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        candidate('a.jpg', takenAtMs: 3000),
        candidate('b.jpg', takenAtMs: 2000),
        candidate('c.jpg', takenAtMs: 1000),
      ]);

      expect(await photos.count(), 3);

      final firstPage = await photos.page(offset: 0, limit: 2);
      expect(firstPage.length, 2);
      // Newest first by default.
      expect(firstPage.first.fileName, 'a.jpg');

      final secondPage = await photos.page(offset: 2, limit: 2);
      expect(secondPage.length, 1);
      expect(secondPage.first.fileName, 'c.jpg');
    });

    test('re-indexing the same path updates instead of duplicating', () async {
      await photos.upsertCandidates(<PhotoCandidate>[candidate('a.jpg')]);
      final inserted = await photos.upsertCandidates(<PhotoCandidate>[
        candidate('a.jpg', takenAtMs: 4000),
      ]);
      expect(inserted, 0);
      expect(await photos.count(), 1);
    });

    test('filters by rating, favourite and folder', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        candidate('a.jpg'),
        candidate('b.jpg'),
        candidate('c.jpg', folder: '/photos/2023'),
      ]);

      final all = await photos.page(offset: 0, limit: 10);
      await photos.setRating(all.first.id, 5);
      await photos.setFavorite(all[1].id, true);

      expect(
        (await photos.page(offset: 0, limit: 10, filter: const PhotoFilter(minRating: 4))).length,
        1,
      );
      expect(
        (await photos.page(offset: 0, limit: 10, filter: const PhotoFilter(favoritesOnly: true))).length,
        1,
      );
      expect(
        (await photos.page(offset: 0, limit: 10, filter: const PhotoFilter(folder: '/photos/2023'))).length,
        1,
      );
    });

    test('marks vanished files as missing and hides them', () async {
      await photos.upsertCandidates(<PhotoCandidate>[candidate('a.jpg')]);
      final row = (await photos.page(offset: 0, limit: 10)).first;
      await photos.markMissing(row.id);
      expect(await photos.count(), 0);
      expect((await photos.page(offset: 0, limit: 10)).length, 0);
    });

    test('search matches file names', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        candidate('beach-sunset.jpg'),
        candidate('office-meeting.jpg'),
      ]);
      final hits = await photos.page(
        offset: 0,
        limit: 10,
        filter: const PhotoFilter(query: 'beach'),
      );
      expect(hits.length, 1);
      expect(hits.first.fileName, 'beach-sunset.jpg');
    });

    test('search survives punctuation and empty input', () async {
      await photos.upsertCandidates(<PhotoCandidate>[candidate('a.jpg')]);
      expect(
        (await photos.page(offset: 0, limit: 10, filter: const PhotoFilter(query: '   '))).length,
        1,
      );
      expect(
        (await photos.page(offset: 0, limit: 10, filter: const PhotoFilter(query: '"()*'))).length,
        isNonNegative,
      );
    });

    test('month buckets are produced newest first', () async {
      final jan = DateTime(2024, 1, 15).millisecondsSinceEpoch;
      final feb = DateTime(2024, 2, 15).millisecondsSinceEpoch;
      await photos.upsertCandidates(<PhotoCandidate>[
        candidate('a.jpg', takenAtMs: jan),
        candidate('b.jpg', takenAtMs: feb),
      ]);
      final buckets = await photos.dateBuckets(const PhotoFilter());
      expect(buckets.first.key, '2024-02');
    });

    test('GPS is stored and readable', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        candidate('geo.jpg', lat: 19.076, lon: 72.8777),
      ]);
      final row = (await photos.page(offset: 0, limit: 1)).first;
      expect(row.hasGps, isTrue);
      expect(row.lat, closeTo(19.076, 1e-6));
    });
  });

  group('albums', () {
    test('add, count, cover and delete', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        candidate('a.jpg'),
        candidate('b.jpg'),
      ]);
      final ids = (await photos.page(offset: 0, limit: 10)).map((p) => p.id).toList();

      final albumId = await albums.create('Trip');
      await albums.addPhotos(albumId, ids);

      final list = await albums.all();
      expect(list.length, 1);
      expect(list.first.name, 'Trip');
      expect(list.first.count, 2);
      expect(list.first.coverPhotoId, isNotNull);

      final inAlbum = await photos.page(
        offset: 0,
        limit: 10,
        filter: PhotoFilter(albumId: albumId),
      );
      expect(inAlbum.length, 2);

      await albums.removePhotos(albumId, <int>[ids.first]);
      expect((await albums.all()).first.count, 1);

      await albums.delete(albumId);
      expect(await albums.all(), isEmpty);
      // Photos are untouched by album deletion.
      expect(await photos.count(), 2);
    });
  });

  group('edits', () {
    test('saving an identity recipe clears the row', () async {
      await photos.upsertCandidates(<PhotoCandidate>[candidate('a.jpg')]);
      final id = (await photos.page(offset: 0, limit: 1)).first.id;

      await edits.save(id, const EditRecipe(brightness: 0.4));
      expect((await edits.recipeFor(id)).brightness, closeTo(0.4, 1e-9));
      expect(await edits.editedCount(), 1);

      await edits.save(id, EditRecipe.empty);
      expect((await edits.recipeFor(id)).isIdentity, isTrue);
      expect(await edits.editedCount(), 0);
    });
  });
}
