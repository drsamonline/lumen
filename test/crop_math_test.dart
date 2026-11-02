import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/models/crop_math.dart';

void main() {
  const square = Size(100, 100);
  const wide = Size(200, 100);

  group('clampUnit', () {
    test('pulls a rectangle back inside the frame', () {
      final r = CropMath.clampUnit(const Rect.fromLTRB(-0.2, -0.1, 1.3, 1.1));
      expect(r, const Rect.fromLTRB(0, 0, 1, 1));
    });

    test('normalises an inverted rectangle', () {
      final r = CropMath.clampUnit(const Rect.fromLTRB(0.8, 0.9, 0.2, 0.1));
      expect(r.left, closeTo(0.2, 1e-9));
      expect(r.top, closeTo(0.1, 1e-9));
      expect(r.right, closeTo(0.8, 1e-9));
      expect(r.bottom, closeTo(0.9, 1e-9));
    });
  });

  group('dragCorner, free', () {
    test('dragging the bottom-right inward shrinks the crop', () {
      final r = CropMath.dragCorner(
        rect: CropMath.full,
        corner: CropMath.bottomRight,
        delta: const Offset(-0.2, -0.3),
        box: square,
      );
      expect(r.left, closeTo(0, 1e-9));
      expect(r.top, closeTo(0, 1e-9));
      expect(r.right, closeTo(0.8, 1e-9));
      expect(r.bottom, closeTo(0.7, 1e-9));
    });

    test('dragging the top-left inward moves that corner only', () {
      final r = CropMath.dragCorner(
        rect: CropMath.full,
        corner: CropMath.topLeft,
        delta: const Offset(0.25, 0.1),
        box: square,
      );
      expect(r.left, closeTo(0.25, 1e-9));
      expect(r.top, closeTo(0.1, 1e-9));
      expect(r.right, closeTo(1, 1e-9));
      expect(r.bottom, closeTo(1, 1e-9));
    });

    test('cannot be dragged outside the frame', () {
      final r = CropMath.dragCorner(
        rect: const Rect.fromLTRB(0.2, 0.2, 0.6, 0.6),
        corner: CropMath.bottomRight,
        delta: const Offset(5, 5),
        box: square,
      );
      expect(r.right, lessThanOrEqualTo(1.0));
      expect(r.bottom, lessThanOrEqualTo(1.0));
    });

    test('never inverts when dragged past the opposite corner', () {
      final r = CropMath.dragCorner(
        rect: CropMath.full,
        corner: CropMath.bottomRight,
        delta: const Offset(-0.99, -0.99),
        box: square,
      );
      expect(r.right, greaterThan(r.left));
      expect(r.bottom, greaterThan(r.top));
      expect(r.width, greaterThanOrEqualTo(CropMath.minSize - 1e-9));
      expect(r.height, greaterThanOrEqualTo(CropMath.minSize - 1e-9));
    });

    test('respects the minimum size on every corner', () {
      for (var corner = 0; corner < 4; corner++) {
        final r = CropMath.dragCorner(
          rect: CropMath.full,
          corner: corner,
          delta: const Offset(0.99, 0.99),
          box: square,
        );
        expect(r.width, greaterThanOrEqualTo(CropMath.minSize - 1e-9), reason: 'corner ' + corner.toString());
        expect(r.height, greaterThanOrEqualTo(CropMath.minSize - 1e-9), reason: 'corner ' + corner.toString());
        expect(r.left, greaterThanOrEqualTo(-1e-9));
        expect(r.top, greaterThanOrEqualTo(-1e-9));
        expect(r.right, lessThanOrEqualTo(1 + 1e-9));
        expect(r.bottom, lessThanOrEqualTo(1 + 1e-9));
      }
    });
  });

  group('dragCorner, aspect locked', () {
    test('a 1:1 lock on a wide frame produces a square in pixels', () {
      final r = CropMath.dragCorner(
        rect: CropMath.full,
        corner: CropMath.bottomRight,
        delta: const Offset(-0.1, 0),
        box: wide,
        aspect: 1.0,
      );
      final widthPx = r.width * wide.width;
      final heightPx = r.height * wide.height;
      expect(widthPx, closeTo(heightPx, 0.5));
    });

    test('a 16:9 lock produces a 16:9 rectangle', () {
      final r = CropMath.dragCorner(
        rect: CropMath.full,
        corner: CropMath.bottomRight,
        delta: const Offset(-0.05, -0.05),
        box: wide,
        aspect: 16 / 9,
      );
      final ratio = (r.width * wide.width) / (r.height * wide.height);
      expect(ratio, closeTo(16 / 9, 0.02));
    });

    test('stays inside the frame while locked', () {
      final r = CropMath.dragCorner(
        rect: CropMath.full,
        corner: CropMath.bottomLeft,
        delta: const Offset(-3, 3),
        box: wide,
        aspect: 1.0,
      );
      expect(r.left, greaterThanOrEqualTo(-1e-9));
      expect(r.right, lessThanOrEqualTo(1 + 1e-9));
      expect(r.top, greaterThanOrEqualTo(-1e-9));
      expect(r.bottom, lessThanOrEqualTo(1 + 1e-9));
    });
  });

  group('fitAspect', () {
    test('fits a square inside a wide box without overflowing', () {
      final r = CropMath.fitAspect(aspect: 1.0, box: wide);
      final widthPx = r.width * wide.width;
      final heightPx = r.height * wide.height;
      expect(widthPx, closeTo(heightPx, 0.5));
      expect(heightPx, closeTo(100, 0.5));
    });

    test('is centred', () {
      final r = CropMath.fitAspect(aspect: 4 / 3, box: wide);
      expect(r.center.dx, closeTo(0.5, 1e-9));
      expect(r.center.dy, closeTo(0.5, 1e-9));
    });

    test('refuses a degenerate box', () {
      expect(CropMath.fitAspect(aspect: 1, box: Size.zero), CropMath.full);
    });
  });

  group('reaspect', () {
    test('keeps the centre and the requested ratio', () {
      const start = Rect.fromLTRB(0.2, 0.2, 0.8, 0.8);
      final r = CropMath.reaspect(start, aspect: 2.0, box: wide);
      expect(r.center.dx, closeTo(start.center.dx, 1e-6));
      expect(r.center.dy, closeTo(start.center.dy, 1e-6));
      final ratio = (r.width * wide.width) / (r.height * wide.height);
      expect(ratio, closeTo(2.0, 0.02));
    });
  });

  group('fromRecipe', () {
    test('treats a degenerate stored crop as no crop', () {
      expect(CropMath.fromRecipe(0.5, 0.5, 0.5, 0.5), CropMath.full);
      expect(CropMath.fromRecipe(0.9, 0.9, 0.1, 0.1), CropMath.full);
    });

    test('keeps a sensible stored crop', () {
      final r = CropMath.fromRecipe(0.1, 0.2, 0.8, 0.9);
      expect(r.left, closeTo(0.1, 1e-9));
      expect(r.bottom, closeTo(0.9, 1e-9));
    });
  });
}
