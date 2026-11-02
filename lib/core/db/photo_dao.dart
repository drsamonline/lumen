import 'package:sqflite/sqflite.dart';

import '../formats/format_registry.dart';
import '../models/photo.dart';
import '../search/fuzzy.dart';
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
    this.nearLat,
    this.nearLon,
    this.radiusDeg = 0.25,
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

  /// A geographic box, not a radius: the index stores plain lat/lon, and a
  /// bounding box is the one query SQLite can answer with a range scan.
  final double? nearLat;
  final double? nearLon;
  final double radiusDeg;

  final PhotoSort sort;

  bool get isActive =>
      query.isNotEmpty ||
      folder != null ||
      albumId != null ||
      personId != null ||
      minRating > 0 ||
      favoritesOnly ||
      fromMs != null ||
      toMs != null ||
      (nearLat != null && nearLon != null);

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
          nearLat == other.nearLat &&
          nearLon == other.nearLon &&
          radiusDeg == other.radiusDeg &&
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
        nearLat,
        nearLon,
        radiusDeg,
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
    double? nearLat,
    double? nearLon,
    double? radiusDeg,
    PhotoSort? sort,
    bool clearFolder = false,
    bool clearAlbum = false,
    bool clearPerson = false,
    bool clearDates = false,
    bool clearPlace = false,
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
      nearLat: clearPlace ? null : (nearLat ?? this.nearLat),
      nearLon: clearPlace ? null : (nearLon ?? this.nearLon),
      radiusDeg: radiusDeg ?? this.radiusDeg,
      sort: sort ?? this.sort,
    );
  }
}

enum PhotoSort { dateTakenDesc, dateTakenAsc, dateAddedDesc, nameAsc }

class PhotoDao {
  PhotoDao(this._appDb);

  final AppDatabase _appDb;
  Database get _db => _appDb.db;

  /// Delegates to the format registry, so a newly installed decoder plugin
  /// makes its formats indexable without touching this class.
  static bool isSupportedExtension(String ext) =>
      ImageFormatRegistry.instance.isSupportedExtension(ext);

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

  Future<void> setDhash(int id, int? hash) async {
    await _db.update(
      'photos',
      <String, Object?>{'dhash': hash},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Photos still waiting for a perceptual hash, newest first so the most
  /// interesting duplicates are found first if the user stops early.
  Future<List<int>> idsMissingHash({int limit = 200000}) async {
    final rows = await _db.query(
      'photos',
      columns: <String>['id'],
      where: 'dhash IS NULL AND missing = 0',
      orderBy: 'taken_at_ms DESC',
      limit: limit,
    );
    return rows.map((r) => r['id'] as int).toList(growable: false);
  }

  Future<List<HashRow>> hashes() async {
    final rows = await _db.query(
      'photos',
      columns: <String>['id', 'dhash'],
      where: 'dhash IS NOT NULL AND missing = 0',
    );
    return rows
        .map((r) => HashRow(id: r['id'] as int, dhash: r['dhash'] as int))
        .toList(growable: false);
  }

  Future<int> countMissingHash() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM photos WHERE dhash IS NULL AND missing = 0',
    );
    return (rows.first['c'] as int?) ?? 0;
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

  /// Bulk rating. One transaction for the whole selection, so marking 400
  /// photos is one write rather than 400.
  Future<void> setRatingMany(List<int> ids, int rating) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await _db.update(
      'photos',
      <String, Object?>{'rating': rating.clamp(0, 5)},
      where: 'id IN ($placeholders)',
      whereArgs: <Object?>[...ids],
    );
  }

  Future<void> setFavoriteMany(List<int> ids, bool favorite) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await _db.update(
      'photos',
      <String, Object?>{'is_favorite': favorite ? 1 : 0},
      where: 'id IN ($placeholders)',
      whereArgs: <Object?>[...ids],
    );
  }

  /// Total bytes of a selection, for the "you are exporting N MB" line.
  Future<int> totalBytes(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(size_bytes), 0) AS total FROM photos WHERE id IN ($placeholders)',
      ids,
    );
    return (rows.first['total'] as int?) ?? 0;
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

  /// Search that degrades gracefully instead of returning nothing.
  ///
  /// 1. the FTS5 / LIKE query the filter already describes (ranked by FTS);
  /// 2. if that is empty, a substring pass over the same fields — this is what
  ///    catches "sunset" inside "beach-sunset-2019";
  /// 3. if that is still empty, an edit-distance pass over file names, so a
  ///    typo ("reciept") still finds "receipt.jpg".
  ///
  /// The mode is reported back so the UI can say what it actually did rather
  /// than silently showing approximate results as if they were exact.
  Future<SearchResult> search(
    PhotoFilter filter, {
    required int offset,
    required int limit,
  }) async {
    final primary = await page(offset: offset, limit: limit, filter: filter);
    final query = filter.query.trim();
    if (primary.isNotEmpty || query.isEmpty) {
      return SearchResult(photos: primary, mode: SearchMode.exact);
    }
    if (query.length < 2) {
      return const SearchResult(photos: <Photo>[], mode: SearchMode.exact);
    }

    final substring = await _pageSubstring(filter, offset: offset, limit: limit);
    if (substring.isNotEmpty) {
      return SearchResult(photos: substring, mode: SearchMode.substring);
    }
    if (query.length < 3) {
      return const SearchResult(photos: <Photo>[], mode: SearchMode.exact);
    }

    final fuzzy = await _pageFuzzy(filter, offset: offset, limit: limit);
    return SearchResult(photos: fuzzy, mode: SearchMode.fuzzy);
  }

  Future<List<Photo>> _pageSubstring(
    PhotoFilter filter, {
    required int offset,
    required int limit,
  }) async {
    final tokens = filter.query
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return const <Photo>[];

    final where = <String>['missing = 0'];
    final args = <Object?>[];
    // Re-use the non-text parts of the filter, then add the substring clauses.
    _applyFilter(filter.copyWith(query: ''), where, args, forCount: true);
    for (final token in tokens) {
      where.add('(file_name LIKE ? OR folder LIKE ? OR caption LIKE ? OR tags LIKE ?)');
      final like = '%$token%';
      args.addAll(<Object?>[like, like, like, like]);
    }
    args.addAll(<Object?>[limit, offset]);
    final rows = await _db.rawQuery(
      'SELECT * FROM photos WHERE ${where.join(' AND ')} '
      'ORDER BY taken_at_ms DESC LIMIT ? OFFSET ?',
      args,
    );
    return rows.map(Photo.fromMap).toList(growable: false);
  }

  Future<List<Photo>> _pageFuzzy(
    PhotoFilter filter, {
    required int offset,
    required int limit,
  }) async {
    final tokens = filter.query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 3)
        .toList();
    if (tokens.isEmpty) return const <Photo>[];

    // Bounded candidate set: scoring every filename in a 500k library would
    // stall the UI, and the newest 8000 is where a typo almost always points.
    final rows = await _db.query(
      'photos',
      columns: <String>['id', 'file_name'],
      where: 'missing = 0',
      orderBy: 'taken_at_ms DESC',
      limit: 8000,
    );

    final scored = <int, int>{};
    for (final row in rows) {
      final name = (row['file_name'] as String).toLowerCase();
      final nameTokens = name
          .replaceAll(RegExp(r'\.[a-z0-9]+$'), '')
          .split(RegExp(r'[^a-z0-9]+'))
          .where((t) => t.isNotEmpty);
      var best = 1 << 30;
      for (final token in tokens) {
        for (final candidate in nameTokens) {
          if (candidate.startsWith(token)) {
            best = 0;
            break;
          }
          final d = Fuzzy.withinOneEdit(token, candidate);
          if (d < best) best = d;
        }
        if (best == 0) break;
      }
      if (best <= 1) scored[row['id'] as int] = best;
    }
    if (scored.isEmpty) return const <Photo>[];

    final ids = scored.keys.toList()
      ..sort((a, b) {
        final byDistance = scored[a]!.compareTo(scored[b]!);
        return byDistance != 0 ? byDistance : b.compareTo(a);
      });
    final window = ids.skip(offset).take(limit).toList();
    if (window.isEmpty) return const <Photo>[];

    final placeholders = List.filled(window.length, '?').join(',');
    final photoRows = await _db.rawQuery(
      'SELECT * FROM photos WHERE id IN ($placeholders)',
      window,
    );
    final byId = <int, Photo>{
      for (final r in photoRows) (r['id'] as int): Photo.fromMap(r),
    };
    return <Photo>[
      for (final id in window)
        if (byId[id] != null) byId[id]!,
    ];
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

  /// Photos grouped into rough places, without any reverse geocoding.
  ///
  /// Coordinates are rounded to one decimal (~11 km at the equator) and grouped
  /// in SQL. No map, no tiles, no network — just "these photos were taken near
  /// here", which is the part of Picasa's Places view that people actually used.
  Future<List<PlaceBucket>> places({int limit = 200}) async {
    final rows = await _db.rawQuery(
      'SELECT ROUND(lat, 1) AS la, ROUND(lon, 1) AS lo, COUNT(*) AS c, '
      'MIN(id) AS sample_id, MIN(taken_at_ms) AS first_ms '
      'FROM photos WHERE missing = 0 AND lat IS NOT NULL AND lon IS NOT NULL '
      'GROUP BY la, lo ORDER BY c DESC LIMIT ?',
      <Object?>[limit],
    );
    return rows
        .map((r) => PlaceBucket(
              lat: (r['la'] as num).toDouble(),
              lon: (r['lo'] as num).toDouble(),
              count: (r['c'] as int?) ?? 0,
              samplePhotoId: r['sample_id'] as int?,
              firstTakenMs: (r['first_ms'] as int?) ?? 0,
            ))
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
    if (filter.nearLat != null && filter.nearLon != null) {
      final r = filter.radiusDeg.abs();
      where.add('lat IS NOT NULL AND lon IS NOT NULL '
          'AND lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?');
      args.addAll(<Object?>[
        filter.nearLat! - r,
        filter.nearLat! + r,
        filter.nearLon! - r,
        filter.nearLon! + r,
      ]);
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

enum SearchMode { exact, substring, fuzzy }

class SearchResult {
  const SearchResult({required this.photos, required this.mode});
  final List<Photo> photos;
  final SearchMode mode;
}

/// One rough place: a rounded coordinate pair and how many photos are there.
class PlaceBucket {
  const PlaceBucket({
    required this.lat,
    required this.lon,
    required this.count,
    required this.samplePhotoId,
    required this.firstTakenMs,
  });

  final double lat;
  final double lon;
  final int count;
  final int? samplePhotoId;
  final int firstTakenMs;

  String get coordinateLabel {
    final ns = lat >= 0 ? 'N' : 'S';
    final ew = lon >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(1)}° $ns, ${lon.abs().toStringAsFixed(1)}° $ew';
  }

  PhotoFilter get filter => PhotoFilter(nearLat: lat, nearLon: lon, radiusDeg: 0.25);
}

class HashRow {
  const HashRow({required this.id, required this.dhash});
  final int id;
  final int dhash;
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
