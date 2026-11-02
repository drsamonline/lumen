import '../models/album.dart';
import 'package:sqflite/sqflite.dart';

import 'database.dart';

class AlbumDao {
  AlbumDao(this._appDb);
  final AppDatabase _appDb;

  Future<List<Album>> all() async {
    final rows = await _appDb.db.rawQuery("""
      SELECT a.id, a.name, a.created_ms, a.cover_photo_id,
             (SELECT COUNT(*) FROM album_photos ap WHERE ap.album_id = a.id) AS count
      FROM albums a
      ORDER BY a.name COLLATE NOCASE ASC
    """);
    return rows.map(Album.fromMap).toList(growable: false);
  }

  Future<int> create(String name) async {
    return _appDb.db.insert('albums', <String, Object?>{
      'name': name,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> rename(int id, String name) async {
    await _appDb.db.update('albums', <String, Object?>{'name': name},
        where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> delete(int id) async {
    await _appDb.db.transaction((txn) async {
      await txn.delete('album_photos', where: 'album_id = ?', whereArgs: <Object?>[id]);
      await txn.delete('albums', where: 'id = ?', whereArgs: <Object?>[id]);
    });
  }

  Future<void> addPhotos(int albumId, List<int> photoIds) async {
    if (photoIds.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = _appDb.db.batch();
    for (final pid in photoIds) {
      batch.insert(
        'album_photos',
        <String, Object?>{'album_id': albumId, 'photo_id': pid, 'added_ms': now},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
    await _refreshCover(albumId);
  }

  Future<void> removePhotos(int albumId, List<int> photoIds) async {
    if (photoIds.isEmpty) return;
    final placeholders = List.filled(photoIds.length, '?').join(',');
    await _appDb.db.delete(
      'album_photos',
      where: 'album_id = ? AND photo_id IN ($placeholders)',
      whereArgs: <Object?>[albumId, ...photoIds],
    );
    await _refreshCover(albumId);
  }

  Future<void> _refreshCover(int albumId) async {
    final rows = await _appDb.db.rawQuery(
      'SELECT photo_id FROM album_photos WHERE album_id = ? '
      'ORDER BY added_ms DESC LIMIT 1',
      <Object?>[albumId],
    );
    final cover = rows.isEmpty ? null : rows.first['photo_id'] as int?;
    await _appDb.db.update('albums', <String, Object?>{'cover_photo_id': cover},
        where: 'id = ?', whereArgs: <Object?>[albumId]);
  }
}
