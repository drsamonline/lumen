import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/db/roots_dao.dart';
import '../core/scan/scanner.dart';
import '../core/scan/watch_service.dart';

/// Wraps the scanner so the UI can show progress without touching dart:io.
class ScanController extends ChangeNotifier {
  ScanController({
    required LibraryScanner scanner,
    required WatchService watcher,
    required RootsDao rootsDao,
  })  : _scanner = scanner,
        _watcher = watcher,
        _rootsDao = rootsDao {
    _sub = _scanner.progress.listen((p) {
      _progress = p;
      if (_alive) notifyListeners();
    });
  }

  final LibraryScanner _scanner;
  final WatchService _watcher;
  final RootsDao _rootsDao;
  StreamSubscription<ScanProgress>? _sub;
  bool _alive = true;

  ScanProgress _progress = const ScanProgress();
  ScanProgress get progress => _progress;

  bool get isScanning => _scanner.isRunning;
  bool get isWatching => _watcher.isWatching;

  Future<ScanProgress> scanAll() async {
    final roots = await _rootsDao.all();
    return _scanner.scanRoots(roots);
  }

  Future<void> ensureWatching({required bool enabled}) async {
    final roots = await _rootsDao.all();
    if (enabled) {
      await _watcher.watch(roots);
    } else {
      await _watcher.stop();
    }
    if (_alive) notifyListeners();
  }

  Future<void> addRoot(String path) async {
    await _rootsDao.add(path);
    await _scanner.scanRoots(<String>[path]);
  }

  Future<void> removeRoot(String path) async {
    await _rootsDao.remove(path);
  }

  @override
  void dispose() {
    _alive = false;
    _sub?.cancel();
    super.dispose();
  }
}
