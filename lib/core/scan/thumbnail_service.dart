import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui' as ui;

import '../app_paths.dart';
import '../db/photo_dao.dart';
import '../formats/format_registry.dart';

/// Generates and caches grid thumbnails.
///
/// Decoding happens inside the Flutter engine (`instantiateImageCodec` with a
/// target width), which downsamples during decode rather than after — roughly
/// 5-10x faster than decoding full resolution and then scaling, and it does not
/// block the UI isolate.
class ThumbnailService {
  ThumbnailService(this._dao);

  final PhotoDao _dao;

  static const int thumbWidth = 480;
  static const int _maxConcurrent = 3;

  final Queue<int> _queue = Queue<int>();
  final Set<int> _queued = <int>{};
  int _active = 0;
  bool _disposed = false;

  final StreamController<int> _ready = StreamController<int>.broadcast();

  /// Emits a photo id every time a thumbnail lands on disk.
  Stream<int> get onReady => _ready.stream;

  int get pending => _queue.length + _active;

  /// Ask for a thumbnail. Cheap and idempotent — the grid calls this for every
  /// visible tile on every rebuild.
  void request(int photoId) {
    if (_disposed) return;
    if (_queued.contains(photoId)) return;
    _queued.add(photoId);
    _queue.add(photoId);
    _pump();
  }

  bool hasThumb(int photoId) => File(AppPaths.thumbPath(photoId)).existsSync();

  void _pump() {
    while (_active < _maxConcurrent && _queue.isNotEmpty) {
      final id = _queue.removeFirst();
      _active++;
      unawaited(_generate(id).whenComplete(() {
        _active--;
        _queued.remove(id);
        _pump();
      }));
    }
  }

  Future<void> _generate(int photoId) async {
    try {
      final target = await AppPaths.thumbFile(photoId);
      if (await target.exists()) {
        await _dao.setThumbReady(photoId, true);
        if (!_ready.isClosed) _ready.add(photoId);
        return;
      }

      final photo = await _dao.byId(photoId);
      if (photo == null) return;

      final source = File(photo.path);
      if (!await source.exists()) {
        await _dao.markMissing(photoId);
        return;
      }

      // Decoding goes through the format registry, so a HEIC or a RAW file
      // produces a thumbnail exactly like a JPEG does.
      final image = await ImageFormatRegistry.instance.decode(
        source,
        targetWidth: thumbWidth,
      );
      if (image == null) return;

      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData == null) return;
      final png = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      await target.writeAsBytes(png, flush: false);

      await _dao.setThumbReady(photoId, true);
      if (!_ready.isClosed) _ready.add(photoId);
    } catch (_) {
      // Unreadable/corrupt file: leave thumb_ready false, the tile shows a
      // placeholder. The next scan pass will retry.
    }
  }

  /// Decode an image at a bounded size for the full-screen viewer, so a 50 MP
  /// file does not allocate 200 MB of RAM.
  static Future<ui.Image?> decodeBounded(String path, {int maxWidth = 2048}) async {
    return ImageFormatRegistry.instance.decode(
      File(path),
      targetWidth: maxWidth,
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    _queue.clear();
    _queued.clear();
    await _ready.close();
  }
}

