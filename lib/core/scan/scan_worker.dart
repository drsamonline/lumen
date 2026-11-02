import 'package:path/path.dart' as p;

import '../db/photo_dao.dart';
import 'capture_date.dart';
import 'exif_reader.dart';

/// One file the walk found that needs its metadata read.
///
/// Plain fields only — this crosses an isolate boundary, so it must not hold
/// anything with a native resource behind it.
class PendingFile {
  const PendingFile({
    required this.path,
    required this.folder,
    required this.fileName,
    required this.ext,
    required this.sizeBytes,
    required this.modifiedMs,
  });

  final String path;
  final String folder;
  final String fileName;
  final String ext;
  final int sizeBytes;
  final int modifiedMs;

  factory PendingFile.of(String path, {required int sizeBytes, required int modifiedMs}) {
    return PendingFile(
      path: path,
      folder: p.dirname(path),
      fileName: p.basename(path),
      ext: p.extension(path).replaceFirst('.', '').toLowerCase(),
      sizeBytes: sizeBytes,
      modifiedMs: modifiedMs,
    );
  }
}

/// Reads EXIF for a batch of files and turns them into index rows.
///
/// This is the CPU-heavy half of a scan: reading up to 512 KB per file and
/// parsing the TIFF structure. It runs in a background isolate through
/// `Isolate.run`, because on the UI isolate it is what makes a first scan of a
/// phone library stutter. It touches no database — the caller does the writing,
/// because sqflite cannot cross an isolate boundary.
Future<List<PhotoCandidate>> readCandidates(List<PendingFile> files) async {
  final out = <PhotoCandidate>[];
  for (final file in files) {
    final exif = await ExifReader.read(file.path);
    out.add(
      PhotoCandidate(
        path: file.path,
        folder: file.folder,
        fileName: file.fileName,
        ext: file.ext,
        sizeBytes: file.sizeBytes,
        modifiedMs: file.modifiedMs,
        takenAtMs: exif.takenAtMs ??
            CaptureDate.fromFileName(file.path) ??
            file.modifiedMs,
        width: exif.width,
        height: exif.height,
        cameraMake: exif.make,
        cameraModel: exif.model,
        iso: exif.iso,
        fNumber: exif.fNumber,
        exposureTime: exif.exposureTime,
        focalLength: exif.focalLength,
        lat: exif.lat,
        lon: exif.lon,
        orientation: exif.orientation,
      ),
    );
  }
  return out;
}
