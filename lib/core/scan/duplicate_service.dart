import '../app_paths.dart';
import '../db/photo_dao.dart';
import '../models/photo.dart';
import 'hash_service.dart';

class DuplicateGroup {
  const DuplicateGroup({required this.photos, required this.maxDistance});

  final List<Photo> photos;

  /// Worst pairwise Hamming distance inside the group. 0 means the files are
  /// visually identical; anything up to the threshold is a re-encode.
  final int maxDistance;

  /// The copy worth keeping: the largest pixel count, then the largest file.
  /// "Keep the best" is the decision the user would have made anyway.
  Photo get best {
    var winner = photos.first;
    for (final photo in photos.skip(1)) {
      final winnerPixels = (winner.width ?? 0) * (winner.height ?? 0);
      final photoPixels = (photo.width ?? 0) * (photo.height ?? 0);
      if (photoPixels > winnerPixels ||
          (photoPixels == winnerPixels && photo.sizeBytes > winner.sizeBytes)) {
        winner = photo;
      }
    }
    return winner;
  }

  int get wastedBytes =>
      photos.where((p) => p.id != best.id).fold(0, (sum, p) => sum + p.sizeBytes);
}

class DuplicateProgress {
  const DuplicateProgress({this.hashed = 0, this.total = 0, this.done = false});
  final int hashed;
  final int total;
  final bool done;
}

/// Finds duplicate photos by perceptual hash.
///
/// Deliberately read-only: Lumen never deletes a photo. It shows you the groups
/// and lets you decide, because a wrong automatic delete is the one mistake a
/// photo library cannot apologise for.
class DuplicateService {
  DuplicateService(this._dao);

  final PhotoDao _dao;

  /// Hash every photo that does not have one yet. Thumbnails are generated on
  /// demand first, since the hash is read from the thumbnail.
  Future<int> hashMissing({
    void Function(DuplicateProgress)? onProgress,
    Future<bool> Function()? shouldStop,
  }) async {
    final pending = await _dao.idsMissingHash();
    var done = 0;
    for (final id in pending) {
      if (shouldStop != null && await shouldStop()) break;
      final hash = await _hashOne(id);
      if (hash != null) await _dao.setDhash(id, hash);
      done++;
      onProgress?.call(DuplicateProgress(hashed: done, total: pending.length));
    }
    onProgress?.call(DuplicateProgress(hashed: done, total: pending.length, done: true));
    return done;
  }

  Future<int?> _hashOne(int photoId) async {
    final photo = await _dao.byId(photoId);
    if (photo == null) return null;

    // Prefer the cached thumbnail; fall back to the original if it is missing.
    var path = await _thumbPathIfPresent(photoId);
    path ??= photo.path;
    final hash = await HashService.hashThumbnailFile(path);
    return hash;
  }

  Future<String?> _thumbPathIfPresent(int photoId) async {
    // AppPaths is initialised by the app; a test that skips it simply falls
    // through to the original file instead of failing.
    try {
      final file = await AppPaths.thumbFile(photoId);
      return await file.exists() ? file.path : null;
    } catch (_) {
      return null;
    }
  }

  /// Group near-identical photos.
  ///
  /// [threshold] is the Hamming distance that still counts as "the same
  /// picture": 0-4 is a re-encode, 5-8 is usually the same shot at different
  /// sizes, above 10 starts merging genuinely different frames.
  Future<List<DuplicateGroup>> findGroups({int threshold = 8}) async {
    final rows = await _dao.hashes();
    if (rows.length < 2) return const <DuplicateGroup>[];

    final parent = List<int>.generate(rows.length, (i) => i);

    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    void union(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[rb] = ra;
    }

    // Candidate buckets: photos sharing any 16-bit band.
    final buckets = <int, List<int>>{};
    for (var i = 0; i < rows.length; i++) {
      for (final band in HashService.bands(rows[i].dhash)) {
        buckets.putIfAbsent(band, () => <int>[]).add(i);
      }
    }

    for (final bucket in buckets.values) {
      if (bucket.length < 2) continue;
      for (var a = 0; a < bucket.length; a++) {
        for (var b = a + 1; b < bucket.length; b++) {
          final i = bucket[a], j = bucket[b];
          if (find(i) == find(j)) continue;
          final d = HashService.hamming(rows[i].dhash, rows[j].dhash);
          if (d <= threshold) union(i, j);
        }
      }
    }

    final byRoot = <int, List<int>>{};
    for (var i = 0; i < rows.length; i++) {
      byRoot.putIfAbsent(find(i), () => <int>[]).add(i);
    }

    final groups = <DuplicateGroup>[];
    for (final members in byRoot.values) {
      if (members.length < 2) continue;
      var worst = 0;
      for (var a = 0; a < members.length; a++) {
        for (var b = a + 1; b < members.length; b++) {
          final d = HashService.hamming(rows[members[a]].dhash, rows[members[b]].dhash);
          if (d > worst) worst = d;
        }
      }
      // One query for the whole group, then restored to group order.
      final fetched = await _dao.byIds(<int>[
        for (final index in members) rows[index].id,
      ]);
      final byId = <int, Photo>{for (final photo in fetched) photo.id: photo};
      final photos = <Photo>[
        for (final index in members)
          if (byId[rows[index].id] case final photo?) photo,
      ];
      if (photos.length >= 2) {
        groups.add(DuplicateGroup(photos: photos, maxDistance: worst));
      }
    }

    groups.sort((a, b) => b.wastedBytes.compareTo(a.wastedBytes));
    return groups;
  }
}
