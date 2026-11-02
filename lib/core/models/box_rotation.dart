import 'dart:ui';

/// Maps a normalised box between the image's own orientation and the way it is
/// displayed after a quarter-turn rotation.
///
/// Faces are stored in the unrotated image's coordinates, because that is what
/// the file contains. The viewer draws the photo rotated, so a box drawn on a
/// turned photo has to be rotated into storage, and a stored box rotated out for
/// display. Without this, tagging a landscape photo that was shot in portrait
/// puts the name on somebody's elbow.
class BoxRotation {
  /// A stored box, expressed in display space. [turns] is 0, 90, 180 or 270.
  static Rect toDisplay(Rect stored, int turns) {
    final r = _normalise(turns);
    final l = stored.left, t = stored.top, w = stored.width, h = stored.height;
    switch (r) {
      case 90:
        return Rect.fromLTWH(1 - (t + h), l, h, w);
      case 180:
        return Rect.fromLTWH(1 - (l + w), 1 - (t + h), w, h);
      case 270:
        return Rect.fromLTWH(t, 1 - (l + w), h, w);
      default:
        return stored;
    }
  }

  /// A box drawn in display space, expressed in the image's own coordinates.
  static Rect fromDisplay(Rect displayed, int turns) {
    final r = _normalise(turns);
    // Rotating back is rotating forward by the complement.
    return toDisplay(displayed, (360 - r) % 360);
  }

  static int _normalise(int turns) {
    final t = turns % 360;
    if (t < 0) return _normalise(t + 360);
    // Nearest quarter turn, not the one below: 359 degrees is upright, and
    // flooring sent it to 270 and drew the box sideways.
    return (t / 90).round() * 90 % 360;
  }
}
