import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/photo_dao.dart';

/// What the thumbnail cache currently holds.
class CacheReport {
  const CacheReport({
    required this.thumbFiles,
    required this.thumbBytes,
    required this.orphanFiles,
    required this.orphanBytes,
    required this.livePhotos,
  });

  final int thumbFiles;
  final int thumbBytes;

  /// Thumbnails whose photo is no longer in the index. Pure waste: nothing can
  /// ever show them again.
  final int orphanFiles;
  final int orphanBytes;

  final int livePhotos;

  int get liveFiles => thumbFiles - orphanFiles;

  /// Roughly what the cache would take if every photo had a thumbnail.
  double get coverage => livePhotos == 0 ? 0 : liveFiles / livePhotos;

  static const CacheReport empty = CacheReport(
    thumbFiles: 0,
    thumbBytes: 0,
    orphanFiles: 0,
    orphanBytes: 0,
    livePhotos: 0,
  );
}

/// Reclaims disk from the thumbnail cache.
///
/// Deliberately narrow. It never touches a photo: thumbnails are derived
/// artefacts that Lumen can rebuild from the original at any time, so deleting
/// one costs a re-render and nothing else. That is what makes this safe enough
/// to offer without a confirmation labyrinth.
class CacheCompactor {
  CacheCompactor(this._dao, this._thumbsDir);

  final PhotoDao _dao;
  final String _thumbsDir;

  /// Reads the cache without changing anything, so the UI can show the numbers
  /// before the user commits.
  Future<CacheReport> survey() async {
    final dir = Directory(_thumbsDir);
    if (!await dir.exists()) {
      return CacheReport(
        thumbFiles: 0,
        thumbBytes: 0,
        orphanFiles: 0,
        orphanBytes: 0,
        livePhotos: await _dao.count(),
      );
    }

    final liveIds = await _dao.allIds();
    var files = 0;
    var bytes = 0;
    var orphans = 0;
    var orphanBytes = 0;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.png')) continue;
      final id = int.tryParse(p.basenameWithoutExtension(entity.path));
      final size = await entity.length().catchError((_) => 0);
      files++;
      bytes += size;
      if (id == null || !liveIds.contains(id)) {
        orphans++;
        orphanBytes += size;
      }
    }

    return CacheReport(
      thumbFiles: files,
      thumbBytes: bytes,
      orphanFiles: orphans,
      orphanBytes: orphanBytes,
      livePhotos: liveIds.length,
    );
  }

  /// Deletes thumbnails nothing can show. Returns the bytes freed.
  Future<int> deleteOrphans() async {
    final dir = Directory(_thumbsDir);
    if (!await dir.exists()) return 0;

    final liveIds = await _dao.allIds();
    var freed = 0;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.png')) continue;
      final id = int.tryParse(p.basenameWithoutExtension(entity.path));
      if (id != null && liveIds.contains(id)) continue;
      try {
        freed += await entity.length();
        await entity.delete();
      } catch (_) {
        // A file that will not delete is not worth failing the whole sweep for.
      }
    }
    return freed;
  }

  /// Deletes the whole cache. Every thumbnail is rebuilt on demand, so this
  /// costs browsing speed once and nothing else.
  Future<int> clearAll() async {
    final dir = Directory(_thumbsDir);
    if (!await dir.exists()) return 0;

    var freed = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        freed += await entity.length();
        await entity.delete();
      } catch (_) {}
    }
    return freed;
  }

  /// Bytes as a short human string. Kept here so the app and the command-line
  /// tool report the same way.
  static String human(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = <String>['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }
}
