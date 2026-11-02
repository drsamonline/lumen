import 'dart:math' as math;
import 'dart:ui';

/// Pure geometry for the crop tool.
///
/// Kept out of the widget so the fiddly part — corner dragging with an aspect
/// lock, clamping, minimum size — can be tested without a render surface.
///
/// A crop rectangle is stored normalised: 0..1 across the image, independent of
/// display size. That is why the same recipe crops correctly in the grid tile,
/// the viewer and an exported full-resolution file.
class CropMath {
  static const double minSize = 0.06;

  /// Corner indices, matching the widget's handle order.
  static const int topLeft = 0;
  static const int topRight = 1;
  static const int bottomRight = 2;
  static const int bottomLeft = 3;

  static Rect full = const Rect.fromLTRB(0, 0, 1, 1);

  static Rect clampUnit(Rect r) {
    final l = r.left.clamp(0.0, 1.0);
    final t = r.top.clamp(0.0, 1.0);
    final rr = r.right.clamp(0.0, 1.0);
    final b = r.bottom.clamp(0.0, 1.0);
    return Rect.fromLTRB(
      math.min(l, rr),
      math.min(t, b),
      math.max(l, rr),
      math.max(t, b),
    );
  }

  /// Move one corner by [delta] (normalised), with the opposite corner pinned.
  ///
  /// [box] is the on-screen size of the preview, needed because [aspect] is a
  /// pixel ratio while the rectangle is normalised — without it a 1:1 crop on a
  /// wide photo would be wrong.
  static Rect dragCorner({
    required Rect rect,
    required int corner,
    required Offset delta,
    required Size box,
    double? aspect,
  }) {
    final isLeft = corner == topLeft || corner == bottomLeft;
    final isTop = corner == topLeft || corner == topRight;

    final anchorX = isLeft ? rect.right : rect.left;
    final anchorY = isTop ? rect.bottom : rect.top;

    var x = (isLeft ? rect.left : rect.right) + delta.dx;
    var y = (isTop ? rect.top : rect.bottom) + delta.dy;

    if (aspect != null && box.width > 0 && box.height > 0) {
      // Room available from the pinned corner in each direction.
      final maxWidthPx = (isLeft ? anchorX : 1 - anchorX) * box.width;
      final maxHeightPx = (isTop ? anchorY : 1 - anchorY) * box.height;

      var widthPx = (x - anchorX).abs() * box.width;
      var heightPx = (y - anchorY).abs() * box.height;

      if (widthPx > 1e-6 && heightPx > 1e-6) {
        // Satisfy the ratio first, then pull back inside the frame. Order
        // matters: clamping after the ratio is what stops a 1:1 lock from
        // silently becoming 16:9 at the edge of a wide photo.
        if (widthPx / heightPx > aspect) {
          heightPx = widthPx / aspect;
        } else {
          widthPx = heightPx * aspect;
        }
        if (widthPx > maxWidthPx) {
          widthPx = maxWidthPx;
          heightPx = widthPx / aspect;
        }
        if (heightPx > maxHeightPx) {
          heightPx = maxHeightPx;
          widthPx = heightPx * aspect;
        }
      }

      x = anchorX + (isLeft ? -widthPx / box.width : widthPx / box.width);
      y = anchorY + (isTop ? -heightPx / box.height : heightPx / box.height);
    }

    // A corner never crosses its anchor, so the rectangle cannot invert.
    if (isLeft) {
      x = x.clamp(0.0, anchorX - minSize);
    } else {
      x = x.clamp(anchorX + minSize, 1.0);
    }
    if (isTop) {
      y = y.clamp(0.0, anchorY - minSize);
    } else {
      y = y.clamp(anchorY + minSize, 1.0);
    }

    return Rect.fromLTRB(
      isLeft ? x : anchorX,
      isTop ? y : anchorY,
      isLeft ? anchorX : x,
      isTop ? anchorY : y,
    );
  }

  /// The largest rectangle of [aspect] (pixel width / height) centred in the
  /// preview. Used by the preset buttons.
  static Rect fitAspect({required double aspect, required Size box}) {
    if (box.width <= 0 || box.height <= 0 || aspect <= 0) return full;
    final boxAspect = box.width / box.height;

    double width;
    double height;
    if (aspect > boxAspect) {
      width = 1.0;
      height = (box.width / aspect) / box.height;
    } else {
      height = 1.0;
      width = (box.height * aspect) / box.width;
    }

    width = width.clamp(minSize, 1.0);
    height = height.clamp(minSize, 1.0);
    return Rect.fromCenter(center: const Offset(0.5, 0.5), width: width, height: height);
  }

  /// Apply [aspect] to an existing rectangle, keeping its centre.
  static Rect reaspect(Rect rect, {required double aspect, required Size box}) {
    if (box.width <= 0 || box.height <= 0 || aspect <= 0) return rect;
    final centre = rect.center;
    final widthPx = rect.width * box.width;
    final heightPx = rect.height * box.height;

    double newWidthPx;
    double newHeightPx;
    if (widthPx / heightPx > aspect) {
      newHeightPx = heightPx;
      newWidthPx = heightPx * aspect;
    } else {
      newWidthPx = widthPx;
      newHeightPx = widthPx / aspect;
    }

    var result = Rect.fromCenter(
      center: centre,
      width: newWidthPx / box.width,
      height: newHeightPx / box.height,
    );
    // Slide back inside the frame rather than letting it overflow.
    result = _shiftInside(result);
    return result;
  }

  static Rect _shiftInside(Rect rect) {
    var dx = 0.0;
    var dy = 0.0;
    if (rect.left < 0) dx = -rect.left;
    if (rect.right > 1) dx = 1 - rect.right;
    if (rect.top < 0) dy = -rect.top;
    if (rect.bottom > 1) dy = 1 - rect.bottom;
    final shifted = rect.shift(Offset(dx, dy));
    return clampUnit(shifted);
  }

  /// Convert a stored recipe crop into a rectangle, tolerating junk values.
  static Rect fromRecipe(double l, double t, double r, double b) {
    final rect = Rect.fromLTRB(l, t, r, b);
    if (rect.width < minSize || rect.height < minSize) return full;
    return clampUnit(rect);
  }
}
