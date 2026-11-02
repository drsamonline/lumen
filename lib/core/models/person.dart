class Person {
  const Person({
    required this.id,
    required this.name,
    this.coverFaceId,
    this.count = 0,
  });

  final int id;
  final String name;
  final int? coverFaceId;
  final int count;

  factory Person.fromMap(Map<String, Object?> m) => Person(
        id: m['id'] as int,
        name: m['name'] as String,
        coverFaceId: m['cover_face_id'] as int?,
        count: (m['count'] as int?) ?? 0,
      );
}

/// A face box, stored in normalised 0..1 coordinates relative to the image.
class Face {
  const Face({
    required this.id,
    required this.photoId,
    this.personId,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final int id;
  final int photoId;
  final int? personId;
  final double x;
  final double y;
  final double w;
  final double h;

  factory Face.fromMap(Map<String, Object?> m) => Face(
        id: m['id'] as int,
        photoId: m['photo_id'] as int,
        personId: m['person_id'] as int?,
        x: (m['x'] as num).toDouble(),
        y: (m['y'] as num).toDouble(),
        w: (m['w'] as num).toDouble(),
        h: (m['h'] as num).toDouble(),
      );
}
