import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/db/album_dao.dart';
import 'package:lumen/core/db/database.dart';
import 'package:lumen/core/db/photo_dao.dart';
import 'package:lumen/core/models/photo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PhotoCandidate named(String name) => PhotoCandidate(
      path: '/photos/$name',
      folder: '/photos',
      fileName: name,
      ext: 'jpg',
      sizeBytes: 1024,
      modifiedMs: 1000,
      takenAtMs: 1000,
    );

void main() {
  late PhotoDao photos;
  late AlbumDao albums;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.open(inMemory: true);
    photos = PhotoDao(AppDatabase.instance);
    albums = AlbumDao(AppDatabase.instance);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  group('three-stage search', () {
    test('an exact token is answered by the index', () async {
      await photos.upsertCandidates(<PhotoCandidate>[named('beach-sunset.jpg')]);
      final result = await photos.search(
        const PhotoFilter(query: 'beach'),
        offset: 0,
        limit: 10,
      );
      expect(result.mode, SearchMode.exact);
      expect(result.photos.length, 1);
    });

    test('a mid-word fragment falls through to substring', () async {
      await photos.upsertCandidates(<PhotoCandidate>[named('beach-sunset.jpg')]);
      final result = await photos.search(
        const PhotoFilter(query: 'each'),
        offset: 0,
        limit: 10,
      );
      expect(result.mode, SearchMode.substring);
      expect(result.photos.single.fileName, 'beach-sunset.jpg');
    });

    test('a typo falls through to edit distance', () async {
      await photos.upsertCandidates(<PhotoCandidate>[named('receipt.jpg')]);
      final result = await photos.search(
        const PhotoFilter(query: 'reciept'),
        offset: 0,
        limit: 10,
      );
      expect(result.mode, SearchMode.fuzzy);
      expect(result.photos.single.fileName, 'receipt.jpg');
    });

    test('a query with no relation returns nothing, not noise', () async {
      await photos.upsertCandidates(<PhotoCandidate>[named('receipt.jpg')]);
      final result = await photos.search(
        const PhotoFilter(query: 'xylophone'),
        offset: 0,
        limit: 10,
      );
      expect(result.photos, isEmpty);
    });
  });

  group('search respects the rest of the filter', () {
    test('substring results stay inside the album', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        named('beach.jpg'),
        named('peach.jpg'),
      ]);
      final rows = await photos.page(offset: 0, limit: 10);
      final beach = rows.firstWhere((p) => p.fileName == 'beach.jpg');
      final albumId = await albums.create('One');
      await albums.addPhotos(albumId, <int>[beach.id]);

      final result = await photos.search(
        PhotoFilter(query: 'each', albumId: albumId),
        offset: 0,
        limit: 10,
      );
      expect(result.photos.length, 1);
      expect(result.photos.single.fileName, 'beach.jpg');
    });

    test('fuzzy results stay inside the album', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        named('sunset.jpg'),
        named('sunsetx.jpg'),
      ]);
      final rows = await photos.page(offset: 0, limit: 10);
      final sunset = rows.firstWhere((p) => p.fileName == 'sunset.jpg');
      final other = rows.firstWhere((p) => p.fileName == 'sunsetx.jpg');

      final albumId = await albums.create('One');
      await albums.addPhotos(albumId, <int>[sunset.id]);

      final result = await photos.search(
        PhotoFilter(query: 'sunsetx', albumId: albumId),
        offset: 0,
        limit: 10,
      );
      // The closer match lives in another album and must not leak in.
      expect(result.photos.every((p) => p.id != other.id), isTrue);
      expect(result.photos.single.fileName, 'sunset.jpg');
    });

    test('fuzzy results respect a star-rating filter', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        named('receipt.jpg'),
        named('receipt-old.jpg'),
      ]);
      final rows = await photos.page(offset: 0, limit: 10);
      final starred = rows.firstWhere((p) => p.fileName == 'receipt.jpg');
      await photos.setRating(starred.id, 5);

      final result = await photos.search(
        const PhotoFilter(query: 'reciept', minRating: 4),
        offset: 0,
        limit: 10,
      );
      expect(result.photos.single.id, starred.id);
    });
  });
}
