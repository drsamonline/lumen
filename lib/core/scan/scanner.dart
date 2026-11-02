import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/database.dart';
import '../db/photo_dao.dart';
import '../models/photo.dart';
import 'exif_reader.dart';

class ScanProgress {
  const ScanProgress({
    this.scanned = 0,
    this.added = 0,
    this.updated = 0,
    this.removed = 0,
    this.current,
    this.done = false,
    this.error,
  });

  final int scanned;
  final int added;
  final int updated;
  final int removed;
  final String? current;
  final bool done;
  final String? error;

  double progressAgainst(int total) => total == 0 ? 0 : (scanned / total).clamp(0.0, 1.0);
}

/// Walks the library roots and keeps the index in sync with the disk.
///
/// The scanner is deliberately incremental: a file whose size and mtime are
/// unchanged is skipped without being opened, so rescanning a 50,000-photo
/// library after adding one folder takes seconds, not minutes.
class LibraryScanner {
  LibraryScanner(this._dao, this._appDb);

  final PhotoDao _dao;
  final AppDatabase _appDb;

  bool _running = false;
  bool get isRunning => _running;

  final StreamController<ScanProgress> _progress =
      StreamController<ScanProgress>.broadcast();
  Stream<ScanProgress> get progress => _progress.stream;

  static const Set<String> _skipDirNames = <String>{
    '.git', '.svn', 'node_modules', r'$RECYCLE.BIN', 'System Volume Information',
    '@eaDir', '.thumbnails', '.cache',
  };

  static bool _isUnderSkippedDir(String root, String path) {
    final relative = p.relative(path, from: root);
    for (final segment in p.split(relative)) {
      if (_skipDirNames.contains(segment)) return true;
    }
    return false;
  }

  /// Cheap pre-filter so we do not stat every file in the tree twice.
  static bool _looksLikeImage(String name) {
    final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
    return PhotoDao.isSupportedExtension(ext);
  }

  Future<ScanProgress> scanRoots(List<String> roots) async {
    if (_running) {
      return const ScanProgress(error: 'A scan is already running');
    }
    _running = true;
    var scanned = 0;
    var added = 0;
    var updated = 0;
    var removed = 0;

    try {
      final batch = <PhotoCandidate>[];
      const batchSize = 150;

      Future<void> flush() async {
        if (batch.isEmpty) return;
        added += await _dao.upsertCandidates(List<PhotoCandidate>.from(batch));
        batch.clear();
      }

      for (final root in roots) {
        final dir = Directory(root);
        if (!await dir.exists()) continue;

        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          // `Directory.list` cannot prune a subtree, so a skipped directory has
          // to be filtered out per entry. Without this, every image inside
          // node_modules or .cache was indexed.
          if (_isUnderSkippedDir(root, entity.path)) continue;
          if (!_looksLikeImage(entity.path)) continue;
          if (entity.path.contains('${p.separator}thumbs${p.separator}')) continue;

          FileStat stat;
          try {
            stat = await entity.stat();
          } catch (_) {
            continue;
          }

          final existing = await _dao.byPath(entity.path);
          if (existing != null &&
              existing.sizeBytes == stat.size &&
              existing.modifiedMs == stat.modified.millisecondsSinceEpoch) {
            continue;
          }

          final exif = await ExifReader.read(entity.path);
          final takenAt = exif.takenAtMs ?? stat.modified.millisecondsSinceEpoch;

          batch.add(PhotoCandidate(
            path: entity.path,
            folder: entity.parent.path,
            fileName: p.basename(entity.path),
            ext: p.extension(entity.path).replaceFirst('.', '').toLowerCase(),
            sizeBytes: stat.size,
            modifiedMs: stat.modified.millisecondsSinceEpoch,
            takenAtMs: takenAt,
            width: exif.width,
            height: exif.height,
            cameraMake: exif.make,
            cameraModel: exif.model,
            iso: exif.iso,
            fNumber: exif.fNumber,
            exposureTime: exif.exposureTime,
            focalLength: exif.focalLength,
            lat: exif.lat,
            lon: exif.lon,
            orientation: exif.orientation,
          ));

          scanned++;
          if (existing != null) updated++;

          if (batch.length >= batchSize) {
            await flush();
            _emit(ScanProgress(
              scanned: scanned,
              added: added,
              updated: updated,
              removed: removed,
              current: p.basename(entity.path),
            ));
            // Yield so the UI can paint during a long scan.
            await Future<void>.delayed(Duration.zero);
          }
        }
      }

      await flush();

      // Anything the walk never touched is gone from disk.
      removed = await _markVanished(roots);

      final finalProgress = ScanProgress(
        scanned: scanned,
        added: added,
        updated: updated,
        removed: removed,
        done: true,
      );
      _emit(finalProgress);
      return finalProgress;
    } catch (e) {
      final failed = ScanProgress(done: true, error: e.toString());
      _emit(failed);
      return failed;
    } finally {
      _running = false;
    }
  }

  /// Re-index a single directory — used by the folder watcher.
  Future<ScanProgress> scanFolder(String folder) => scanRoots(<String>[folder]);

  Future<int> _markVanished(List<String> roots) async {
    if (roots.isEmpty) return 0;
    final rows = await _appDb.db.query(
      'photos',
      columns: <String>['id', 'path'],
      where: 'missing = 0',
    );
    var removed = 0;
    for (final row in rows) {
      final path = row['path'] as String;
      final underRoot = roots.any((r) => path.startsWith(r));
      if (!underRoot) continue;
      if (!await File(path).exists()) {
        await _dao.markMissing(row['id'] as int);
        removed++;
      }
    }
    return removed;
  }

  void _emit(ScanProgress p) {
    if (!_progress.isClosed) _progress.add(p);
  }

  Future<void> dispose() => _progress.close();
}
