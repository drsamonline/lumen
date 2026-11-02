import 'package:sqflite/sqflite.dart';

import 'database.dart';

class RootsDao {
  RootsDao(this._appDb);
  final AppDatabase _appDb;

  Future<List<String>> all() async {
    final rows = await _appDb.db.query('library_roots', orderBy: 'id ASC');
    return rows.map((r) => r['path'] as String).toList(growable: false);
  }

  Future<void> add(String path) async {
    await _appDb.db.insert(
      'library_roots',
      <String, Object?>{
        'path': path,
        'added_ms': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> remove(String path) async {
    await _appDb.db
        .delete('library_roots', where: 'path = ?', whereArgs: <Object?>[path]);
  }
}
