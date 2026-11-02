import 'package:sqflite/sqflite.dart';

/// The single SQLite index that drives the whole app.
///
/// Design notes:
/// * WAL + NORMAL sync: fast writes, safe against app crashes (not against
///   power loss, which is an acceptable trade for a photo index that can be
///   rebuilt by rescanning).
/// * Thumbnails live on disk, not as blobs, so the database stays small enough
///   to sit in the OS page cache.
/// * FTS5 is used when the platform SQLite has it; otherwise search falls back
///   to LIKE. [ftsEnabled] tells the DAO which path to take.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  bool ftsEnabled = false;

  bool get isOpen => _db != null;

  Database get db {
    final d = _db;
    if (d == null) {
      throw StateError('Database is not open. Call AppDatabase.instance.open().');
    }
    return d;
  }

  Future<void> open({String? path, bool inMemory = false}) async {
    if (_db != null) return;
    // The path is passed in rather than resolved here. `path_provider` is a
    // Flutter plugin, and this file has to compile into the command-line tool,
    // where there is no engine to call it.
    final target = inMemory ? inMemoryDatabasePath : path;
    if (target == null) {
      throw ArgumentError(
        'AppDatabase.open needs a path (or inMemory: true).',
      );
    }

    _db = await databaseFactory.openDatabase(
      target,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (d) async {
          // Pragmas go through rawQuery, never execute.
          //
          // `PRAGMA journal_mode = WAL` returns a row, and the Android plugin
          // rejects execute() for anything that returns rows:
          //   "Queries can be performed using SQLiteDatabase query or rawQuery
          //    methods only."
          // The FFI factory used on desktop is permissive about this, so the
          // difference only ever showed up on a phone.
          await _pragma(d, 'PRAGMA foreign_keys = ON');
          if (!inMemory) {
            await _pragma(d, 'PRAGMA journal_mode = WAL');
          }
          await _pragma(d, 'PRAGMA synchronous = NORMAL');
          await _pragma(d, 'PRAGMA temp_store = MEMORY');
          await _pragma(d, 'PRAGMA cache_size = -16000');
        },
        onCreate: (d, version) => _createSchema(d),
        onUpgrade: (d, from, to) async {
          // v2 adds the perceptual hash used for duplicate detection. Older
          // libraries simply get the column; a duplicate scan backfills it.
          if (from < 2) {
            await d.execute('ALTER TABLE photos ADD COLUMN dhash INTEGER');
            await d.execute('CREATE INDEX IF NOT EXISTS idx_photos_dhash ON photos(dhash)');
          }
        },
      ),
    );

    await _tryCreateFts();
  }

  /// A pragma is an optimisation. If one is unsupported or refused, the app must
  /// still open — a photo library that will not start because it could not set a
  /// cache size is not a photo library.
  static Future<void> _pragma(Database d, String sql) async {
    try {
      await d.rawQuery(sql);
    } catch (_) {
      // Ignored on purpose.
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _createSchema(Database d) async {
    final batch = d.batch();

    batch.execute("""
      CREATE TABLE photos (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        path          TEXT    NOT NULL UNIQUE,
        folder        TEXT    NOT NULL,
        file_name     TEXT    NOT NULL,
        ext           TEXT    NOT NULL,
        size_bytes    INTEGER NOT NULL DEFAULT 0,
        modified_ms   INTEGER NOT NULL DEFAULT 0,
        taken_at_ms   INTEGER NOT NULL DEFAULT 0,
        width         INTEGER,
        height        INTEGER,
        camera_make   TEXT,
        camera_model  TEXT,
        iso           INTEGER,
        f_number      REAL,
        exposure_time TEXT,
        focal_length  REAL,
        lat           REAL,
        lon           REAL,
        orientation   INTEGER NOT NULL DEFAULT 1,
        rating        INTEGER NOT NULL DEFAULT 0,
        is_favorite   INTEGER NOT NULL DEFAULT 0,
        caption       TEXT,
        tags          TEXT,
        thumb_ready   INTEGER NOT NULL DEFAULT 0,
        missing       INTEGER NOT NULL DEFAULT 0,
        indexed_ms    INTEGER NOT NULL DEFAULT 0,
        dhash         INTEGER
      )
    """);

    batch.execute('CREATE INDEX idx_photos_taken ON photos(taken_at_ms DESC)');
    batch.execute('CREATE INDEX idx_photos_folder ON photos(folder)');
    batch.execute('CREATE INDEX idx_photos_thumb ON photos(thumb_ready)');
    batch.execute('CREATE INDEX idx_photos_rating ON photos(rating)');
    batch.execute('CREATE INDEX idx_photos_dhash ON photos(dhash)');

    batch.execute("""
      CREATE TABLE library_roots (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        path     TEXT NOT NULL UNIQUE,
        added_ms INTEGER NOT NULL DEFAULT 0
      )
    """);

    batch.execute("""
      CREATE TABLE albums (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        name           TEXT NOT NULL,
        cover_photo_id INTEGER,
        created_ms     INTEGER NOT NULL DEFAULT 0
      )
    """);

    batch.execute("""
      CREATE TABLE album_photos (
        album_id INTEGER NOT NULL,
        photo_id INTEGER NOT NULL,
        added_ms INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (album_id, photo_id)
      )
    """);
    batch.execute('CREATE INDEX idx_album_photos_photo ON album_photos(photo_id)');

    batch.execute("""
      CREATE TABLE people (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        name          TEXT NOT NULL UNIQUE,
        cover_face_id INTEGER
      )
    """);

    batch.execute("""
      CREATE TABLE faces (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        photo_id  INTEGER NOT NULL,
        person_id INTEGER,
        x         REAL NOT NULL,
        y         REAL NOT NULL,
        w         REAL NOT NULL,
        h         REAL NOT NULL
      )
    """);
    batch.execute('CREATE INDEX idx_faces_photo ON faces(photo_id)');
    batch.execute('CREATE INDEX idx_faces_person ON faces(person_id)');

    batch.execute("""
      CREATE TABLE edits (
        photo_id   INTEGER PRIMARY KEY,
        recipe     TEXT NOT NULL,
        updated_ms INTEGER NOT NULL DEFAULT 0
      )
    """);

    batch.execute("""
      CREATE TABLE scan_log (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        started_ms INTEGER NOT NULL,
        ended_ms   INTEGER,
        added      INTEGER NOT NULL DEFAULT 0,
        updated    INTEGER NOT NULL DEFAULT 0,
        removed    INTEGER NOT NULL DEFAULT 0
      )
    """);

    await batch.commit(noResult: true);
  }

  /// FTS5 is present in the FFI build and in every modern Android SQLite.
  /// If it is missing we degrade gracefully rather than failing to start.
  Future<void> _tryCreateFts() async {
    try {
      await db.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS photos_fts USING fts5(
          file_name, folder, caption, tags,
          content='photos', content_rowid='id', tokenize='unicode61'
        )
      """);
      await db.execute("""
        CREATE TRIGGER IF NOT EXISTS photos_ai AFTER INSERT ON photos BEGIN
          INSERT INTO photos_fts(rowid, file_name, folder, caption, tags)
          VALUES (new.id, new.file_name, new.folder, new.caption, new.tags);
        END
      """);
      await db.execute("""
        CREATE TRIGGER IF NOT EXISTS photos_ad AFTER DELETE ON photos BEGIN
          INSERT INTO photos_fts(photos_fts, rowid, file_name, folder, caption, tags)
          VALUES ('delete', old.id, old.file_name, old.folder, old.caption, old.tags);
        END
      """);
      await db.execute("""
        CREATE TRIGGER IF NOT EXISTS photos_au AFTER UPDATE ON photos BEGIN
          INSERT INTO photos_fts(photos_fts, rowid, file_name, folder, caption, tags)
          VALUES ('delete', old.id, old.file_name, old.folder, old.caption, old.tags);
          INSERT INTO photos_fts(rowid, file_name, folder, caption, tags)
          VALUES (new.id, new.file_name, new.folder, new.caption, new.tags);
        END
      """);
      ftsEnabled = true;

      // Backfill if the virtual table is empty but photos already exist.
      final ftsCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM photos_fts'),
          ) ??
          0;
      final photoCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM photos'),
          ) ??
          0;
      if (ftsCount == 0 && photoCount > 0) {
        await db.execute("INSERT INTO photos_fts(photos_fts) VALUES('rebuild')");
      }
    } catch (_) {
      ftsEnabled = false;
    }
  }
}
