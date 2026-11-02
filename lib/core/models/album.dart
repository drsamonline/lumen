class Album {
  const Album({
    required this.id,
    required this.name,
    required this.createdMs,
    this.coverPhotoId,
    this.count = 0,
  });

  final int id;
  final String name;
  final int createdMs;
  final int? coverPhotoId;
  final int count;

  factory Album.fromMap(Map<String, Object?> m) => Album(
        id: m['id'] as int,
        name: m['name'] as String,
        createdMs: (m['created_ms'] as int?) ?? 0,
        coverPhotoId: m['cover_photo_id'] as int?,
        count: (m['count'] as int?) ?? 0,
      );
}
