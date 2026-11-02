import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/album_dao.dart';
import '../core/db/database.dart';
import '../core/db/edit_dao.dart';
import '../core/db/person_dao.dart';
import '../core/db/photo_dao.dart';
import '../core/db/roots_dao.dart';
import '../core/lan/lan_beacon.dart';
import '../core/lan/lan_server.dart';
import '../core/scan/scanner.dart';
import '../core/scan/thumbnail_service.dart';
import '../core/scan/watch_service.dart';
import '../core/settings.dart';
import 'library_controller.dart';
import 'scan_controller.dart';

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase.instance);

final photoDaoProvider = Provider<PhotoDao>((ref) => PhotoDao(ref.watch(databaseProvider)));
final albumDaoProvider = Provider<AlbumDao>((ref) => AlbumDao(ref.watch(databaseProvider)));
final personDaoProvider = Provider<PersonDao>((ref) => PersonDao(ref.watch(databaseProvider)));
final editDaoProvider = Provider<EditDao>((ref) => EditDao(ref.watch(databaseProvider)));
final rootsDaoProvider = Provider<RootsDao>((ref) => RootsDao(ref.watch(databaseProvider)));

final settingsProvider = Provider<Settings>((ref) => Settings.instance);

final libraryRootsProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(rootsDaoProvider).all(),
);

final thumbnailServiceProvider = Provider<ThumbnailService>((ref) {
  final service = ThumbnailService(ref.watch(photoDaoProvider));
  ref.onDispose(service.dispose);
  return service;
});

final scannerProvider = Provider<LibraryScanner>((ref) {
  final scanner = LibraryScanner(
    ref.watch(photoDaoProvider),
    ref.watch(databaseProvider),
  );
  ref.onDispose(scanner.dispose);
  return scanner;
});

final watchServiceProvider = Provider<WatchService>((ref) {
  final watcher = WatchService(ref.watch(scannerProvider));
  ref.onDispose(watcher.dispose);
  return watcher;
});

final lanServerProvider = Provider<LanServer>((ref) {
  final server = LanServer(
    ref.watch(photoDaoProvider),
    ref.watch(editDaoProvider),
  );
  ref.onDispose(server.stop);
  return server;
});

final lanBeaconProvider = Provider<LanBeacon>((ref) {
  final beacon = LanBeacon();
  ref.onDispose(beacon.stop);
  return beacon;
});

final libraryControllerProvider =
    ChangeNotifierProvider<LibraryController>((ref) {
  final controller = LibraryController(
    dao: ref.watch(photoDaoProvider),
    thumbs: ref.watch(thumbnailServiceProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// A scoped controller for one album.
final albumLibraryProvider =
    ChangeNotifierProvider.family<LibraryController, int>((ref, albumId) {
  final controller = LibraryController(
    dao: ref.watch(photoDaoProvider),
    thumbs: ref.watch(thumbnailServiceProvider),
  );
  ref.onDispose(controller.dispose);
  controller.setFilter(PhotoFilter(albumId: albumId));
  return controller;
});

/// A scoped controller for one person.
final personLibraryProvider =
    ChangeNotifierProvider.family<LibraryController, int>((ref, personId) {
  final controller = LibraryController(
    dao: ref.watch(photoDaoProvider),
    thumbs: ref.watch(thumbnailServiceProvider),
  );
  ref.onDispose(controller.dispose);
  controller.setFilter(PhotoFilter(personId: personId));
  return controller;
});

/// A scoped controller for one search. Keyed by the filter itself, which is
/// value-equal, so an identical search reuses the same instance.
final searchLibraryProvider =
    ChangeNotifierProvider.family<LibraryController, PhotoFilter>((ref, filter) {
  final controller = LibraryController(
    dao: ref.watch(photoDaoProvider),
    thumbs: ref.watch(thumbnailServiceProvider),
  );
  ref.onDispose(controller.dispose);
  controller.setFilter(filter);
  return controller;
});

final scanControllerProvider = ChangeNotifierProvider<ScanController>((ref) {
  return ScanController(
    scanner: ref.watch(scannerProvider),
    watcher: ref.watch(watchServiceProvider),
    rootsDao: ref.watch(rootsDaoProvider),
  );
});

/// Albums, refreshed on demand.
final albumsProvider = FutureProvider((ref) => ref.watch(albumDaoProvider).all());

/// People, refreshed on demand.
final peopleProvider = FutureProvider((ref) => ref.watch(personDaoProvider).all());
