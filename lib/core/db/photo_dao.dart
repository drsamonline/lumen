import 'package:sqflite/sqflite.dart';

import '../models/photo.dart';
import 'database.dart';

/// Which slice of the library the grid is showing.
class PhotoFilter {
  const PhotoFilter({
    this.query = '',
    this.folder,
    this.albumId,
    this.personId,
    this.minRating = 0,
    this.favoritesOnly = false,
    this.fromMs,
    this.toMs,
    this.sort = PhotoSort.dateTakenDesc,
  });

  final String query;
  final String? folder;
  final int? albumId;
  final int? personId;
  final int minRating;
  final bool favoritesOnly;
  final int? fromMs;
  final int? toMs;
  final PhotoSort sort;

  bool get isActive =>
      query.isNotEmpty ||
      folder != null ||
      albumId != null ||
      personId != null ||
      minRating > 0 ||
      favoritesOnly ||
      fromMs != null ||
      toMs != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoFilter &&
          query == other.query &&
          folder == other.folder &&
          albumId == other.albumId &&
          personId == other.personId &&
          minRating == other.minRating &&
          favoritesOnly == other.favoritesOnly &&
          fromMs == other.fromMs &&
          toMs == other.toMs &&
          sort == other.sort;

  @override
  int get hashCode => Object.hash(
        query,
        folder,
        albumId,
        personId,
        minRating,
        favoritesOnly,
        fromMs,
        toMs,
        sort,
      );

  PhotoFilter copyWith({
    String? query,
    String? folder,
    int? albumId,
    int? personId,
    int? minRating,
    bool? favoritesOnly,
    int? fromMs,
    int? toMs,
    PhotoSort? sort,
    bool clearFolder = false,
    bool clearAlbum = false,
    bool clearPerson = false,
    bool clearDates = false,
  }) {
    return PhotoFilter(
      query: query ?? this.query,
      folder: clearFolder ? null : (folder ?? this.folder),
      albumId: clearAlbum ? null : (albumId ?? this.albumId),
      personId: clearPerson ? null : (personId ?? this.personId),
      minRating: minRating ?? this.minRating,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      fromMs: clearDates ? null : (fromMs ?? this.fromMs),
      toMs: clearDates ? null : (toMs ?? this.toMs),
      sort: sort ?? this.sort,
    );
  }
}

enum PhotoSort { dateTakenDesc, dateTakenAsc, dateAddedDesc, nameAsc }

class PhotoDao {
  PhotoDao(this._appDb);

  final AppDatabase _appDb;
  Database get _db => _appDb.db;

  static const _imageExtensions = <String>{
    'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'jfif',
  };

  static bool isSupportedExtension(String ext) =>
      _imageExtensions.contains(ext.toLowerCase());

  // ------------------------------------------------------------------ writes

  /// Bulk upsert used by the scanner. Returns the number of genuinely new rows.
  Future<int> upsertCandidates(List<PhotoCandidate> batch) async {
    if (batch.isEmpty) return 0;
    var inserted = 0;
    await _db.transaction((txn) async {
      for (final c in batch) {
        final existing = await txn.query(
          'photos',
          columns: <String>['id'],
          where: 'path = ?',
          whereArgs: <Object?>[c.path],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert('photos', c.toMap());
          inserted++;
        } else {
          await txn.update(
            'photos',
            c.toMap(),
            where: 'id = ?',
            whereArgs: <Object?>[existing.first['id']],
          );
        }
      }
    });
    return inserted;
  }

  Future<void> markMissing(int id) async {
    await _db.update('photos', <String, Object?>{'missing': 1},
        where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> deleteMissing() async {
    await _db.delete('photos', where: 'missing = 1');
  }

  Future<void> setThumbReady(int id, bool ready) async {
    await _db.update(
      'photos',
      <String, Object?>{'thumb_ready': ready ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> setRating(int id, int rating) async {
    await _db.update(
      'photos',
      <String, Object?>{'rating': rating.clamp(0, 5)},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> setFavorite(int id, bool favorite) async {
    await _db.update(
      'photos',
      <String, Object?>{'is_favorite': favorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> setCaption(int id, String? caption) async {
    await _db.update(
      'photos',
      <String, Object?>{'caption': caption},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> setTags(int id, String? tags) async {
    await _db.update(
      'photos',
      <String, Object?>{'tags': tags},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  // ------------------------------------------------------------------- reads

  Future<Photo?> byId(int id) async {
    final rows = await _db.query('photos', where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    if (rows.isEmpty) return null;
    return Photo.fromMap(rows.first);
  }

  Future<Photo?> byPath(String path) async {
    final rows = await _db.query('photos',
        where: 'path = ?', whereArgs: <Object?>[path], limit: 1);
    if (rows.isEmpty) return null;
    return Photo.fromMap(rows.first);
  }

  Future<int> count([PhotoFilter filter = const PhotoFilter()]) async {
    final where = <String>['missing = 0'];
    final args = <Object?>[];
    _applyFilter(filter, where, args, forCount: true);
    final sql = 'SELECT COUNT(*) FROM photos WHERE ${where.join(' AND ')}';
    return Sqflite.firstIntValue(await _db.rawQuery(sql, args)) ?? 0;
  }

  Future<List<Photo>> page({
    required int offset,
    required int limit,
    PhotoFilter filter = const PhotoFilter(),
  }) async {
    final where = <String>['missing = 0'];
    final args = <Object?>[];
    _applyFilter(filter, where, args);
    args.addAll(<Object?>[limit, offset]);
    final sql = 'SELECT * FROM photos WHERE ${where.join(' AND ')} '
        'ORDER BY ${_orderBy(filter.sort)} LIMIT ? OFFSET ?';
    final rows = await _db.rawQuery(sql, args);
    return rows.map(Photo.fromMap).toList(growable: false);
  }

  /// Ids of every photo matching a filter — used by the LAN gallery and by
  /// "select all" in album editing.
  Future<List<int>> idsFor(PhotoFilter filter, {int? limit}) async {
    final where = <String>['missing = 0'];
    final args = <Object?>[];
    _applyFilter(filter, where, args);
    final sql = 'SELECT id FROM photos WHERE ${where.join(' AND ')} '
        'ORDER BY ${_orderBy(filter.sort)}${limit != null ? ' LIMIT ?' : ''}';
    if (limit != null) args.add(limit);
    final rows = await _db.rawQuery(sql, args);
    return rows.map((r) => r['id'] as int).toList(growable: false);
  }

  /// Month buckets for the sticky timeline headers.
  Future<List<DateBucket>> dateBuckets(PhotoFilter filter) async {
    final where = <String>['missing = 0'];
    final args = <Object?>[];
    _applyFilter(filter, where, args, forCount: true);
    final sql = """
      SELECT strftime('%Y-%m', taken_at_ms / 1000, 'unixepoch', 'localtime') AS ym,
             COUNT(*) AS c
      FROM photos
      WHERE ${where.join(' AND ')}
      GROUP BY ym
      ORDER BY ym DESC
    """;
    final rows = await _db.rawQuery(sql, args);
    return rows
        .map((r) => DateBucket(key: (r['ym'] as String?) ?? 'unknown', count: (r['c'] as int?) ?? 0))
        .toList(growable: false);
  }

  Future<List<String>> folders() async {
    final rows = await _db.rawQuery(
      'SELECT folder, COUNT(*) AS c FROM photos WHERE missing = 0 '
      'GROUP BY folder ORDER BY c DESC',
    );
    return rows.map((r) => r['folder'] as String).toList(growable: false);
  }

  Future<List<CameraBucket>> cameras() async {
    final rows = await _db.rawQuery(
      'SELECT camera_model AS m, COUNT(*) AS c FROM photos '
      "WHERE missing = 0 AND camera_model IS NOT NULL AND camera_model <> '' "
      'GROUP BY m ORDER BY c DESC LIMIT 40',
    );
    return rows
        .map((r) => CameraBucket(model: r['m'] as String, count: (r['c'] as int?) ?? 0))
        .toList(growable: false);
  }

  // ------------------------------------------------------------------ filters

  void _applyFilter(
    PhotoFilter filter,
    List<String> where,
    List<Object?> args, {
    bool forCount = false,
  }) {
    if (filter.folder != null) {
      where.add('folder = ?');
      args.add(filter.folder);
    }
    if (filter.albumId != null) {
      where.add('id IN (SELECT photo_id FROM album_photos WHERE album_id = ?)');
      args.add(filter.albumId);
    }
    if (filter.personId != null) {
      where.add('id IN (SELECT photo_id FROM faces WHERE person_id = ?)');
      args.add(filter.personId);
    }
    if (filter.minRating > 0) {
      where.add('rating >= ?');
      args.add(filter.minRating);
    }
    if (filter.favoritesOnly) {
      where.add('is_favorite = 1');
    }
    if (filter.fromMs != null) {
      where.add('taken_at_ms >= ?');
      args.add(filter.fromMs);
    }
    if (filter.toMs != null) {
      where.add('taken_at_ms <= ?');
      args.add(filter.toMs);
    }

    final q = filter.query.trim();
    if (q.isNotEmpty) {
      if (_appDb.ftsEnabled) {
        final fts = _toFtsQuery(q);
        if (fts != null) {
          where.add('id IN (SELECT rowid FROM photos_fts WHERE photos_fts MATCH ?)');
          args.add(fts);
          return;
        }
      }
      // Fallback for platforms without FTS5, or for queries FTS cannot parse.
      where.add('(file_name LIKE ? OR folder LIKE ? OR caption LIKE ? OR tags LIKE ?)');
      final like = '%$q%';
      args.addAll(<Object?>[like, like, like, like]);
    }
  }

  /// Turn user text into a safe FTS5 expression: every token quoted, prefix
  /// matched, joined with AND. Returns null if the input has no usable tokens.
  static String? _toFtsQuery(String raw) {
    final tokens = raw
        .split(RegExp(r'\s+'))
        // Keep only letters, digits and underscore. FTS5 treats punctuation as
        // syntax, and one stray bracket from a user turns into an exception.
        .map((t) => t.replaceAll(RegExp(r'[^\p{L}\p{N}_]', unicode: true), ''))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;
    return tokens.map((t) => '"$t"*').join(' AND ');
  }

  String _orderBy(PhotoSort sort) {
    switch (sort) {
      case PhotoSort.dateTakenDesc:
        return 'taken_at_ms DESC, id DESC';
      case PhotoSort.dateTakenAsc:
        return 'taken_at_ms ASC, id ASC';
      case PhotoSort.dateAddedDesc:
        return 'indexed_ms DESC, id DESC';
      case PhotoSort.nameAsc:
        return 'file_name COLLATE NOCASE ASC';
    }
  }
}

class DateBucket {
  const DateBucket({required this.key, required this.count});
  final String key; // yyyy-MM
  final int count;
}

class CameraBucket {
  const CameraBucket({required this.model, required this.count});
  final String model;
  final int count;
}
