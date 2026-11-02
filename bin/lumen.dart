// Lumen, headless.
//
// The same index, scanner and cache tools as the app, with no Flutter engine
// behind them — which is why `dart compile exe` can build this into a single
// native binary. It shares `lib/core` with the app; what it cannot do is render,
// because thumbnails and image decoding need `dart:ui`.
//
//   dart run bin/lumen.dart --help
//   dart compile exe bin/lumen.dart -o lumen
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lumen/core/db/database.dart';
import 'package:lumen/core/db/photo_dao.dart';
import 'package:lumen/core/db/roots_dao.dart';
import 'package:lumen/core/models/photo.dart';
import 'package:lumen/core/scan/cache_compactor.dart';
import 'package:lumen/core/scan/scanner.dart';

const _usage = '''
Lumen — headless

  lumen scan [--root DIR]...      index the library (or one extra folder)
  lumen roots                     list the indexed folders
  lumen add-root DIR              add a folder to the library
  lumen stats                     what the index holds
  lumen search QUERY              file names, folders, captions, tags
  lumen recent [N]                the N most recent photos (default 20)
  lumen compact [--orphans|--all] [--yes]
                                  reclaim disk from the thumbnail cache
  lumen --help

Options
  --data-dir DIR    where the index lives (default: the platform's data dir)
  --json            machine-readable output where it makes sense

The index is the same file the app uses, so `lumen scan` in a terminal and a
rescan in the app are the same operation.
''';

Future<void> main(List<String> argv) async {
  final args = _Args(argv);
  if (args.has('help') || argv.isEmpty) {
    stdout.writeln(_usage);
    return;
  }

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dataDir = args.dataDir;
  await Directory(dataDir).create(recursive: true);

  final db = AppDatabase.instance;
  await db.open(path: p.join(dataDir, 'lumen.db'));

  final photos = PhotoDao(db);
  final roots = RootsDao(db);

  try {
    switch (args.command) {
      case 'scan':
        await _scan(photos, roots, args);
      case 'roots':
        await _roots(roots);
      case 'add-root':
        await _addRoot(roots, args);
      case 'stats':
        await _stats(photos, roots, dataDir);
      case 'search':
        await _search(photos, args);
      case 'recent':
        await _recent(photos, args);
      case 'compact':
        await _compact(photos, dataDir, args);
      default:
        stderr.writeln('unknown command: ${args.command}');
        stdout.writeln(_usage);
        exitCode = 2;
    }
  } finally {
    await db.close();
  }
}

Future<void> _scan(PhotoDao photos, RootsDao roots, _Args args) async {
  for (final root in args.values('root')) {
    await roots.add(root);
  }
  final folders = await roots.all();
  if (folders.isEmpty) {
    stderr.writeln('No folders to scan. Use --root DIR or `lumen add-root DIR`.');
    exitCode = 1;
    return;
  }

  final scanner = LibraryScanner(photos, AppDatabase.instance);
  final subscription = scanner.progress.listen((progress) {
    if (!progress.done && progress.current != null) {
      stdout.write('\r${progress.scanned}  ${progress.current}'.padRight(78));
    }
  });
  final finalProgress = await scanner.scanRoots(folders);
  await subscription.cancel();
  stdout.writeln(
    'done: ${finalProgress.scanned} read, ${finalProgress.added} new, '
    '${finalProgress.updated} updated, ${finalProgress.removed} missing',
  );
}

Future<void> _roots(RootsDao roots) async {
  final folders = await roots.all();
  if (folders.isEmpty) {
    stdout.writeln('no folders indexed');
    return;
  }
  for (final folder in folders) {
    stdout.writeln(folder);
  }
}

Future<void> _addRoot(RootsDao roots, _Args args) async {
  final dir = args.positional.isEmpty ? null : args.positional.first;
  if (dir == null) {
    stderr.writeln('usage: lumen add-root DIR');
    exitCode = 2;
    return;
  }
  if (!await Directory(dir).exists()) {
    stderr.writeln('not a directory: $dir');
    exitCode = 1;
    return;
  }
  await roots.add(dir);
  stdout.writeln('added $dir');
}

Future<void> _stats(PhotoDao photos, RootsDao roots, String dataDir) async {
  final total = await photos.count();
  final favourites = await photos.count(const PhotoFilter(favoritesOnly: true));
  final withGps = await photos.countWithGps();
  final folders = await roots.all();

  stdout
    ..writeln('index      ${p.join(dataDir, 'lumen.db')}')
    ..writeln('photos     $total')
    ..writeln('favourites $favourites')
    ..writeln('with GPS   $withGps')
    ..writeln('folders    ${folders.length}');
}

Future<void> _search(PhotoDao photos, _Args args) async {
  final query = args.positional.join(' ').trim();
  if (query.isEmpty) {
    stderr.writeln('usage: lumen search QUERY');
    exitCode = 2;
    return;
  }
  final result = await photos.search(PhotoFilter(query: query), offset: 0, limit: 200);
  if (result.photos.isEmpty) {
    stdout.writeln('no matches');
    return;
  }
  if (result.mode != SearchMode.exact) {
    stderr.writeln('(${result.mode.name} matches)');
  }
  for (final photo in result.photos) {
    stdout.writeln(photo.path);
  }
}

Future<void> _recent(PhotoDao photos, _Args args) async {
  final n = args.positional.isEmpty ? 20 : int.tryParse(args.positional.first) ?? 20;
  final rows = await photos.page(offset: 0, limit: n);
  for (final Photo photo in rows) {
    stdout.writeln('${photo.takenAt.toIso8601String().split('.').first}  ${photo.path}');
  }
}

Future<void> _compact(PhotoDao photos, String dataDir, _Args args) async {
  final compactor = CacheCompactor(photos, p.join(dataDir, 'thumbs'));
  final report = await compactor.survey();

  stdout
    ..writeln('thumbnails  ${report.thumbFiles} · ${CacheCompactor.human(report.thumbBytes)}')
    ..writeln('photos      ${report.livePhotos}')
    ..writeln('orphans     ${report.orphanFiles} · ${CacheCompactor.human(report.orphanBytes)}');

  final all = args.has('all');
  final orphansOnly = args.has('orphans') || !all;
  if (report.orphanFiles == 0 && !all) {
    stdout.writeln('nothing to reclaim');
    return;
  }
  if (!args.has('yes')) {
    stdout.writeln('dry run — add --yes to delete');
    return;
  }

  final freed = orphansOnly ? await compactor.deleteOrphans() : await compactor.clearAll();
  stdout.writeln('freed ${CacheCompactor.human(freed)}');
}

/// Minimal flag parser: no dependency, no surprises.
class _Args {
  _Args(List<String> argv) {
    for (var i = 0; i < argv.length; i++) {
      final arg = argv[i];
      if (arg.startsWith('--')) {
        final name = arg.substring(2);
        if (name == 'data-dir' && i + 1 < argv.length) {
          dataDirOverride = argv[++i];
        } else if (name == 'root' && i + 1 < argv.length) {
          _multi.putIfAbsent('root', () => <String>[]).add(argv[++i]);
        } else {
          _flags.add(name);
        }
      } else if (command == null) {
        command = arg;
      } else {
        positional.add(arg);
      }
    }
  }

  String? command;
  String? dataDirOverride;
  final List<String> positional = <String>[];
  final Set<String> _flags = <String>{};
  final Map<String, List<String>> _multi = <String, List<String>>{};

  bool has(String flag) => _flags.contains(flag);
  List<String> values(String name) => _multi[name] ?? const <String>[];

  /// `--data-dir`, then `LUMEN_DATA_DIR`, then the platform's own location.
  String get dataDir {
    if (dataDirOverride != null) return dataDirOverride!;
    final env = Platform.environment['LUMEN_DATA_DIR'];
    if (env != null && env.isNotEmpty) return env;

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) return p.join(appData, 'lumen');
      return p.join(Directory.current.path, '.lumen');
    }
    final xdg = Platform.environment['XDG_DATA_HOME'];
    if (xdg != null && xdg.isNotEmpty) return p.join(xdg, 'lumen');
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) return p.join(home, '.local', 'share', 'lumen');
    return p.join(Directory.current.path, '.lumen');
  }
}
