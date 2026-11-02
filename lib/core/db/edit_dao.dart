import '../models/edit_recipe.dart';
import 'package:sqflite/sqflite.dart';

import 'database.dart';

class EditDao {
  EditDao(this._appDb);
  final AppDatabase _appDb;

  Future<EditRecipe> recipeFor(int photoId) async {
    final rows = await _appDb.db.query('edits',
        where: 'photo_id = ?', whereArgs: <Object?>[photoId], limit: 1);
    if (rows.isEmpty) return EditRecipe.empty;
    return EditRecipe.decode(rows.first['recipe'] as String?);
  }

  Future<Map<int, EditRecipe>> recipesFor(Iterable<int> photoIds) async {
    final ids = photoIds.toList();
    if (ids.isEmpty) return <int, EditRecipe>{};
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await _appDb.db.rawQuery(
      'SELECT photo_id, recipe FROM edits WHERE photo_id IN ($placeholders)',
      ids,
    );
    final out = <int, EditRecipe>{};
    for (final r in rows) {
      out[r['photo_id'] as int] = EditRecipe.decode(r['recipe'] as String?);
    }
    return out;
  }

  Future<void> save(int photoId, EditRecipe recipe) async {
    if (recipe.isIdentity) {
      await clear(photoId);
      return;
    }
    await _appDb.db.insert(
      'edits',
      <String, Object?>{
        'photo_id': photoId,
        'recipe': recipe.encode(),
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clear(int photoId) async {
    await _appDb.db.delete('edits', where: 'photo_id = ?', whereArgs: <Object?>[photoId]);
  }

  Future<int> editedCount() async {
    final rows = await _appDb.db.rawQuery('SELECT COUNT(*) AS c FROM edits');
    return (rows.first['c'] as int?) ?? 0;
  }
}
