import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Everything Lumen writes lives under one application-support directory.
/// Nothing is written outside it, and nothing is read from the network.
class AppPaths {
  static late Directory support;
  static late Directory thumbs;
  static late Directory exports;

  static Future<void> init() async {
    support = await getApplicationSupportDirectory();
    thumbs = Directory(p.join(support.path, 'thumbs'));
    exports = Directory(p.join(support.path, 'exports'));
    await thumbs.create(recursive: true);
    await exports.create(recursive: true);
  }

  static String get dbPath => p.join(support.path, 'lumen.db');

  /// Thumbnails are sharded into 1000-id buckets so no directory ever grows
  /// past a few thousand entries — this keeps directory listing fast on
  /// spinning disks and on Android's slower filesystems.
  static String thumbPath(int photoId) =>
      p.join(thumbs.path, '${photoId ~/ 1000}', '$photoId.png');

  static Future<File> thumbFile(int photoId) async {
    final f = File(thumbPath(photoId));
    if (!await f.parent.exists()) {
      await f.parent.create(recursive: true);
    }
    return f;
  }

  static bool isThumbPath(String path) => path.startsWith(thumbs.path);
}
