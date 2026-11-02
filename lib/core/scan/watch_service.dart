import 'dart:async';
import 'dart:io';

import 'package:watcher/watcher.dart';

import 'scanner.dart';

/// Watches library roots and rescans just the folder that changed.
///
/// Bursts of filesystem events (copying a folder of 400 photos) are coalesced
/// into one rescan per folder per [debounce] window.
class WatchService {
  WatchService(this._scanner);

  final LibraryScanner _scanner;
  final List<DirectoryWatcher> _watchers = <DirectoryWatcher>[];
  final List<StreamSubscription<WatchEvent>> _subs = <StreamSubscription<WatchEvent>>[];
  final Map<String, Timer> _debounce = <String, Timer>{};

  static const Duration _quiet = Duration(seconds: 3);

  bool get isWatching => _watchers.isNotEmpty;

  Future<void> watch(List<String> roots) async {
    await stop();
    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      try {
        final watcher = DirectoryWatcher(root);
        _watchers.add(watcher);
        _subs.add(watcher.events.listen((event) => _onEvent(root, event)));
      } catch (_) {
        // Watching is a convenience; scanning still works without it.
      }
    }
  }

  void _onEvent(String root, WatchEvent event) {
    final path = event.path;
    if (path.isEmpty) return;
    final parent = File(path).parent.path;
    if (!parent.startsWith(root)) return;

    _debounce[parent]?.cancel();
    _debounce[parent] = Timer(_quiet, () {
      _debounce.remove(parent);
      if (_scanner.isRunning) {
        // Reschedule rather than pile up overlapping scans.
        _debounce[parent] = Timer(_quiet, () {
          _debounce.remove(parent);
          unawaited(_scanner.scanFolder(parent));
        });
        return;
      }
      unawaited(_scanner.scanFolder(parent));
    });
  }

  Future<void> stop() async {
    for (final t in _debounce.values) {
      t.cancel();
    }
    _debounce.clear();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _watchers.clear();
  }

  Future<void> dispose() => stop();
}
