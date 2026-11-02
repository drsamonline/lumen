import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/db/database.dart';
import 'package:lumen/core/db/photo_dao.dart';
import 'package:lumen/core/models/photo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PhotoCandidate at(String name, {double? lat, double? lon}) => PhotoCandidate(
      path: '/photos/$name',
      folder: '/photos',
      fileName: name,
      ext: 'jpg',
      sizeBytes: 1024,
      modifiedMs: 1000,
      takenAtMs: 1000,
      lat: lat,
      lon: lon,
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

  group('places', () {
    test('groups photos by rounded coordinate', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        at('a.jpg', lat: 19.076, lon: 72.877),
        at('b.jpg', lat: 19.079, lon: 72.881),
        at('c.jpg', lat: 28.613, lon: 77.209),
      ]);
      final places = await photos.places();
      expect(places.length, 2);
      // Largest group first.
      expect(places.first.count, 2);
      expect(places.first.lat, closeTo(19.1, 0.001));
    });

    test('ignores photos with no GPS', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        at('a.jpg', lat: 19.076, lon: 72.877),
        at('no-gps.jpg'),
      ]);
      final places = await photos.places();
      expect(places.length, 1);
      expect(places.first.count, 1);
    });

    test('returns nothing for a library without coordinates', () async {
      await photos.upsertCandidates(<PhotoCandidate>[at('a.jpg')]);
      expect(await photos.places(), isEmpty);
    });

    test('labels hemispheres correctly', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        at('s.jpg', lat: -33.868, lon: 151.209),
      ]);
      final place = (await photos.places()).first;
      expect(place.coordinateLabel, contains('S'));
      expect(place.coordinateLabel, contains('E'));
    });
  });

  group('geographic filter', () {
    test('keeps only photos inside the box', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        at('mumbai.jpg', lat: 19.076, lon: 72.877),
        at('delhi.jpg', lat: 28.613, lon: 77.209),
      ]);

      final near = await photos.page(
        offset: 0,
        limit: 10,
        filter: const PhotoFilter(nearLat: 19.1, nearLon: 72.9, radiusDeg: 0.25),
      );
      expect(near.length, 1);
      expect(near.first.fileName, 'mumbai.jpg');
    });

    test('excludes photos without coordinates', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        at('geo.jpg', lat: 19.076, lon: 72.877),
        at('plain.jpg'),
      ]);
      final near = await photos.page(
        offset: 0,
        limit: 10,
        filter: const PhotoFilter(nearLat: 19.076, nearLon: 72.877),
      );
      expect(near.length, 1);
    });

    test('counts agree with the page', () async {
      await photos.upsertCandidates(<PhotoCandidate>[
        at('a.jpg', lat: 19.0, lon: 72.8),
        at('b.jpg', lat: 19.1, lon: 72.9),
        at('c.jpg', lat: 40.0, lon: 40.0),
      ]);
      const filter = PhotoFilter(nearLat: 19.05, nearLon: 72.85, radiusDeg: 0.2);
      expect(await photos.count(filter), 2);
      expect((await photos.page(offset: 0, limit: 10, filter: filter)).length, 2);
    });

    test('the filter is value-equal, so it can key a provider', () {
      const a = PhotoFilter(nearLat: 19.0, nearLon: 72.0, radiusDeg: 0.25);
      const b = PhotoFilter(nearLat: 19.0, nearLon: 72.0, radiusDeg: 0.25);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.isActive, isTrue);
    });

    test('clearPlace removes the box', () {
      const filter = PhotoFilter(nearLat: 19.0, nearLon: 72.0);
      final cleared = filter.copyWith(clearPlace: true);
      expect(cleared.nearLat, isNull);
      expect(cleared.nearLon, isNull);
      expect(cleared.isActive, isFalse);
    });
  });
}
