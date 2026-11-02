import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/db/photo_dao.dart';
import '../core/models/photo.dart';
import '../core/scan/thumbnail_service.dart';

/// Owns the photo grid's data window.
///
/// Paging is fixed-size and append-only; a rebuild of the widget tree never
/// re-queries SQLite. That is what keeps scrolling a 100,000-photo library at
/// 60 fps.
class LibraryController extends ChangeNotifier {
  LibraryController({required PhotoDao dao, required ThumbnailService thumbs})
      : _dao = dao,
        _thumbs = thumbs {
    _thumbSub = _thumbs.onReady.listen((_) {
      // A thumbnail landed: rebuild so the tile swaps its placeholder.
      if (_alive) notifyListeners();
    });
  }

  final PhotoDao _dao;
  final ThumbnailService _thumbs;
  StreamSubscription<int>? _thumbSub;
  bool _alive = true;

  static const int pageSize = 120;

  PhotoFilter _filter = const PhotoFilter();
  PhotoFilter get filter => _filter;

  final List<Photo> _photos = <Photo>[];
  List<Photo> get photos => List<Photo>.unmodifiable(_photos);

  int _total = 0;
  int get total => _total;

  bool _loading = false;
  bool get isLoading => _loading;

  bool _loadingMore = false;
  bool get isLoadingMore => _loadingMore;

  bool get hasMore => _photos.length < _total;

  List<DateBucket> _buckets = const <DateBucket>[];
  List<DateBucket> get buckets => _buckets;

  String? _error;
  String? get error => _error;

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _total = await _dao.count(_filter);
      final page = await _dao.page(offset: 0, limit: pageSize, filter: _filter);
      _photos
        ..clear()
        ..addAll(page);
      _buckets = await _dao.dateBuckets(_filter);
      _requestThumbs(page);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      if (_alive) notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || _loading || !hasMore) return;
    _loadingMore = true;
    if (_alive) notifyListeners();
    try {
      final page = await _dao.page(
        offset: _photos.length,
        limit: pageSize,
        filter: _filter,
      );
      _photos.addAll(page);
      _requestThumbs(page);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loadingMore = false;
      if (_alive) notifyListeners();
    }
  }

  Future<void> setFilter(PhotoFilter filter) async {
    _filter = filter;
    await refresh();
  }

  Future<void> clearFilter() => setFilter(const PhotoFilter());

  void _requestThumbs(List<Photo> page) {
    for (final photo in page) {
      if (!photo.thumbReady) _thumbs.request(photo.id);
    }
  }

  /// Called by a grid tile when its thumbnail file is missing.
  void requestThumb(int photoId) => _thumbs.request(photoId);

  // -------------------------------------------------------------- mutations

  Future<void> toggleFavorite(Photo photo) async {
    final next = !photo.isFavorite;
    await _dao.setFavorite(photo.id, next);
    _replace(photo.id, photo.copyWith(isFavorite: next));
  }

  Future<void> setFavoriteFlag(Photo photo, bool favorite) async {
    await _dao.setFavorite(photo.id, favorite);
    _replace(photo.id, photo.copyWith(isFavorite: favorite));
  }

  Future<void> setRating(Photo photo, int rating) async {
    await _dao.setRating(photo.id, rating);
    _replace(photo.id, photo.copyWith(rating: rating));
  }

  Future<void> setCaption(Photo photo, String? caption) async {
    await _dao.setCaption(photo.id, caption);
    _replace(photo.id, photo.copyWith(caption: caption));
  }

  void _replace(int id, Photo updated) {
    final index = _photos.indexWhere((p) => p.id == id);
    if (index >= 0) {
      _photos[index] = updated;
      if (_alive) notifyListeners();
    }
  }

  @override
  void dispose() {
    _alive = false;
    _thumbSub?.cancel();
    super.dispose();
  }
}
