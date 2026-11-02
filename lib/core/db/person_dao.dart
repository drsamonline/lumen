import '../models/person.dart';
import 'database.dart';

class PersonDao {
  PersonDao(this._appDb);
  final AppDatabase _appDb;

  Future<List<Person>> all() async {
    final rows = await _appDb.db.rawQuery("""
      SELECT p.id, p.name, p.cover_face_id,
             (SELECT COUNT(DISTINCT f.photo_id) FROM faces f WHERE f.person_id = p.id) AS count
      FROM people p
      ORDER BY p.name COLLATE NOCASE ASC
    """);
    return rows.map(Person.fromMap).toList(growable: false);
  }

  Future<int> createOrGet(String name) async {
    final existing = await _appDb.db.query('people',
        where: 'name = ? COLLATE NOCASE', whereArgs: <Object?>[name], limit: 1);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return _appDb.db.insert('people', <String, Object?>{'name': name});
  }

  Future<void> rename(int id, String name) async {
    await _appDb.db.update('people', <String, Object?>{'name': name},
        where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> delete(int id) async {
    await _appDb.db.transaction((txn) async {
      await txn.update('faces', <String, Object?>{'person_id': null},
          where: 'person_id = ?', whereArgs: <Object?>[id]);
      await txn.delete('people', where: 'id = ?', whereArgs: <Object?>[id]);
    });
  }

  Future<int> addFace({
    required int photoId,
    required double x,
    required double y,
    required double w,
    required double h,
    int? personId,
  }) async {
    return _appDb.db.insert('faces', <String, Object?>{
      'photo_id': photoId,
      'person_id': personId,
      'x': x,
      'y': y,
      'w': w,
      'h': h,
    });
  }

  Future<List<Face>> facesFor(int photoId) async {
    final rows = await _appDb.db
        .query('faces', where: 'photo_id = ?', whereArgs: <Object?>[photoId]);
    return rows.map(Face.fromMap).toList(growable: false);
  }

  Future<void> assignFace(int faceId, int? personId) async {
    await _appDb.db.update('faces', <String, Object?>{'person_id': personId},
        where: 'id = ?', whereArgs: <Object?>[faceId]);
  }

  Future<void> deleteFace(int faceId) async {
    await _appDb.db.delete('faces', where: 'id = ?', whereArgs: <Object?>[faceId]);
  }
}
