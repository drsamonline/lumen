import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

/// One indexed image file. Immutable; mutations go through [copyWith] so the
/// UI layer can diff cheaply.
class Photo {
  const Photo({
    required this.id,
    required this.path,
    required this.folder,
    required this.fileName,
    required this.ext,
    required this.sizeBytes,
    required this.modifiedMs,
    required this.takenAtMs,
    this.width,
    this.height,
    this.cameraMake,
    this.cameraModel,
    this.iso,
    this.fNumber,
    this.exposureTime,
    this.focalLength,
    this.lat,
    this.lon,
    this.orientation = 1,
    this.rating = 0,
    this.isFavorite = false,
    this.caption,
    this.tags,
    this.thumbReady = false,
    this.missing = false,
  });

  final int id;
  final String path;
  final String folder;
  final String fileName;
  final String ext;
  final int sizeBytes;
  final int modifiedMs;
  final int takenAtMs;
  final int? width;
  final int? height;
  final String? cameraMake;
  final String? cameraModel;
  final int? iso;
  final double? fNumber;
  final String? exposureTime;
  final double? focalLength;
  final double? lat;
  final double? lon;
  final int orientation;
  final int rating;
  final bool isFavorite;
  final String? caption;
  final String? tags;
  final bool thumbReady;
  final bool missing;

  DateTime get takenAt => DateTime.fromMillisecondsSinceEpoch(takenAtMs);

  String get folderName => p.basename(folder);

  String get dimensions {
    if (width == null || height == null) return '—';
    return '$width x $height';
  }

  String get cameraLabel {
    final bits = <String>[
      if (cameraMake != null && cameraMake!.isNotEmpty) cameraMake!,
      if (cameraModel != null && cameraModel!.isNotEmpty) cameraModel!,
    ];
    return bits.isEmpty ? 'Unknown camera' : bits.join(' ');
  }

  String get exposureLabel {
    final parts = <String>[
      if (exposureTime != null) exposureTime!,
      if (fNumber != null) 'f/${fNumber!.toStringAsFixed(1)}',
      if (iso != null) 'ISO $iso',
      if (focalLength != null) '${focalLength!.toStringAsFixed(0)}mm',
    ];
    return parts.isEmpty ? '—' : parts.join('  ');
  }

  bool get hasGps => lat != null && lon != null;

  String get takenLabel => DateFormat('d MMM yyyy, h:mm a').format(takenAt);

  Photo copyWith({
    int? rating,
    bool? isFavorite,
    String? caption,
    String? tags,
    bool? thumbReady,
    bool? missing,
    int? takenAtMs,
    int? width,
    int? height,
  }) {
    return Photo(
      id: id,
      path: path,
      folder: folder,
      fileName: fileName,
      ext: ext,
      sizeBytes: sizeBytes,
      modifiedMs: modifiedMs,
      takenAtMs: takenAtMs ?? this.takenAtMs,
      width: width ?? this.width,
      height: height ?? this.height,
      cameraMake: cameraMake,
      cameraModel: cameraModel,
      iso: iso,
      fNumber: fNumber,
      exposureTime: exposureTime,
      focalLength: focalLength,
      lat: lat,
      lon: lon,
      orientation: orientation,
      rating: rating ?? this.rating,
      isFavorite: isFavorite ?? this.isFavorite,
      caption: caption ?? this.caption,
      tags: tags ?? this.tags,
      thumbReady: thumbReady ?? this.thumbReady,
      missing: missing ?? this.missing,
    );
  }

  factory Photo.fromMap(Map<String, Object?> m) {
    return Photo(
      id: m['id'] as int,
      path: m['path'] as String,
      folder: m['folder'] as String,
      fileName: m['file_name'] as String,
      ext: m['ext'] as String,
      sizeBytes: (m['size_bytes'] as int?) ?? 0,
      modifiedMs: (m['modified_ms'] as int?) ?? 0,
      takenAtMs: (m['taken_at_ms'] as int?) ?? 0,
      width: m['width'] as int?,
      height: m['height'] as int?,
      cameraMake: m['camera_make'] as String?,
      cameraModel: m['camera_model'] as String?,
      iso: m['iso'] as int?,
      fNumber: (m['f_number'] as num?)?.toDouble(),
      exposureTime: m['exposure_time'] as String?,
      focalLength: (m['focal_length'] as num?)?.toDouble(),
      lat: (m['lat'] as num?)?.toDouble(),
      lon: (m['lon'] as num?)?.toDouble(),
      orientation: (m['orientation'] as int?) ?? 1,
      rating: (m['rating'] as int?) ?? 0,
      isFavorite: ((m['is_favorite'] as int?) ?? 0) == 1,
      caption: m['caption'] as String?,
      tags: m['tags'] as String?,
      thumbReady: ((m['thumb_ready'] as int?) ?? 0) == 1,
      missing: ((m['missing'] as int?) ?? 0) == 1,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'path': path,
        'folder': folder,
        'file_name': fileName,
        'ext': ext,
        'size_bytes': sizeBytes,
        'modified_ms': modifiedMs,
        'taken_at_ms': takenAtMs,
        'width': width,
        'height': height,
        'camera_make': cameraMake,
        'camera_model': cameraModel,
        'iso': iso,
        'f_number': fNumber,
        'exposure_time': exposureTime,
        'focal_length': focalLength,
        'lat': lat,
        'lon': lon,
        'orientation': orientation,
        'rating': rating,
        'is_favorite': isFavorite ? 1 : 0,
        'caption': caption,
        'tags': tags,
        'thumb_ready': thumbReady ? 1 : 0,
        'missing': missing ? 1 : 0,
      };
}

/// A mutable staging record used by the scanner before it has a row id.
class PhotoCandidate {
  const PhotoCandidate({
    required this.path,
    required this.folder,
    required this.fileName,
    required this.ext,
    required this.sizeBytes,
    required this.modifiedMs,
    required this.takenAtMs,
    this.width,
    this.height,
    this.cameraMake,
    this.cameraModel,
    this.iso,
    this.fNumber,
    this.exposureTime,
    this.focalLength,
    this.lat,
    this.lon,
    this.orientation = 1,
  });

  final String path;
  final String folder;
  final String fileName;
  final String ext;
  final int sizeBytes;
  final int modifiedMs;
  final int takenAtMs;
  final int? width;
  final int? height;
  final String? cameraMake;
  final String? cameraModel;
  final int? iso;
  final double? fNumber;
  final String? exposureTime;
  final double? focalLength;
  final double? lat;
  final double? lon;
  final int orientation;

  Map<String, Object?> toMap() => <String, Object?>{
        'path': path,
        'folder': folder,
        'file_name': fileName,
        'ext': ext,
        'size_bytes': sizeBytes,
        'modified_ms': modifiedMs,
        'taken_at_ms': takenAtMs,
        'width': width,
        'height': height,
        'camera_make': cameraMake,
        'camera_model': cameraModel,
        'iso': iso,
        'f_number': fNumber,
        'exposure_time': exposureTime,
        'focal_length': focalLength,
        'lat': lat,
        'lon': lon,
        'orientation': orientation,
        'indexed_ms': DateTime.now().millisecondsSinceEpoch,
      };
}
