import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A pragma must never go through `execute`.
///
/// `PRAGMA journal_mode = WAL` returns a row, and sqflite's Android plugin
/// rejects execute() for anything that returns rows. The FFI factory used on
/// desktop tolerates it, so this shipped as a blank screen on a phone and was
/// invisible to every test that ran on the desktop path.
void main() {
  test('no pragma is executed with execute()', () {
    final offenders = <String>[];
    final pattern = RegExp(
      "execute\\(\\s*['\"]\\s*PRAGMA",
      caseSensitive: false,
    );

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final line in source.split('\n')) {
        if (pattern.hasMatch(line)) offenders.add('${entity.path}: ${line.trim()}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Use rawQuery for pragmas — execute() refuses row-returning '
          'statements on Android.\n${offenders.join('\n')}',
    );
  });

  test('the pragma helper is not allowed to throw', () {
    final source = File('lib/core/db/database.dart').readAsStringSync();
    expect(
      source.contains('static Future<void> _pragma'),
      isTrue,
      reason: 'every pragma must go through the guarded helper',
    );
    // The helper body must swallow failures, or one unsupported pragma stops
    // the whole app from opening its index.
    final body = source.substring(source.indexOf('static Future<void> _pragma'));
    expect(body.contains('catch'), isTrue);
  });
}
