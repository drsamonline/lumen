import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/photo.dart';
import 'zip_writer.dart';

class ZipExportResult {
  const ZipExportResult({
    required this.file,
    required this.count,
    required this.bytes,
    required this.skipped,
  });

  final File file;
  final int count;
  final int bytes;

  /// Photos whose original could not be read (unmounted drive, permissions).
  final int skipped;

  String get sizeLabel =>
      bytes < 1024 * 1024 ? '${(bytes / 1024).round()} KB' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Bundles photos into a store-only ZIP on disk.
///
/// Shared by the album export and the multi-select export so both behave
/// identically — one streaming writer, one naming rule, one report.
class AlbumZip {
  static Future<ZipExportResult> export({
    required List<Photo> photos,
    required String directory,
    required String baseName,
  }) async {
    final safeName = baseName
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    final target = File(
      p.join(directory, '${safeName.isEmpty ? 'lumen-export' : safeName}.zip'),
    );

    final sources = <ZipSource>[];
    var skipped = 0;
    var index = 0;

    for (final photo in photos) {
      final file = File(photo.path);
      if (!await file.exists()) {
        skipped++;
        continue;
      }
      index++;
      // Numbered so the archive keeps the album's order and two photos with the
      // same filename cannot collide.
      sources.add(ZipSource.file('${index.toString().padLeft(3, '0')}-${photo.fileName}', file));
    }

    final bytes = await ZipArchiveWriter.write(target, sources);
    return ZipExportResult(
      file: target,
      count: sources.length,
      bytes: bytes,
      skipped: skipped,
    );
  }
}
