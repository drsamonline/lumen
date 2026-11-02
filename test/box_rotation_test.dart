import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/models/box_rotation.dart';

void main() {
  const box = Rect.fromLTWH(0.1, 0.2, 0.3, 0.4);

  void expectRect(Rect actual, Rect expected) {
    expect(actual.left, closeTo(expected.left, 1e-9));
    expect(actual.top, closeTo(expected.top, 1e-9));
    expect(actual.width, closeTo(expected.width, 1e-9));
    expect(actual.height, closeTo(expected.height, 1e-9));
  }

  test('no rotation is the identity', () {
    expectRect(BoxRotation.toDisplay(box, 0), box);
    expectRect(BoxRotation.fromDisplay(box, 0), box);
  });

  test('a quarter turn swaps the sides', () {
    final d = BoxRotation.toDisplay(box, 90);
    expectRect(d, const Rect.fromLTWH(1 - 0.6, 0.1, 0.4, 0.3));
  });

  test('a half turn mirrors both axes', () {
    expectRect(
      BoxRotation.toDisplay(box, 180),
      const Rect.fromLTWH(1 - 0.4, 1 - 0.6, 0.3, 0.4),
    );
  });

  test('three quarter turns mirrors the other way', () {
    expectRect(
      BoxRotation.toDisplay(box, 270),
      const Rect.fromLTWH(0.2, 1 - 0.4, 0.4, 0.3),
    );
  });

  group('round trips', () {
    for (final turns in <int>[0, 90, 180, 270]) {
      test('$turns degrees', () {
        final displayed = BoxRotation.toDisplay(box, turns);
        expectRect(BoxRotation.fromDisplay(displayed, turns), box);
      });
    }
  });

  test('stays inside the frame for every turn', () {
    for (final turns in <int>[0, 90, 180, 270]) {
      final d = BoxRotation.toDisplay(box, turns);
      expect(d.left, greaterThanOrEqualTo(-1e-9));
      expect(d.top, greaterThanOrEqualTo(-1e-9));
      expect(d.right, lessThanOrEqualTo(1 + 1e-9));
      expect(d.bottom, lessThanOrEqualTo(1 + 1e-9));
    }
  });

  test('an odd angle is rounded to the nearest quarter turn', () {
    expectRect(BoxRotation.toDisplay(box, 95), BoxRotation.toDisplay(box, 90));
    expectRect(BoxRotation.toDisplay(box, 359), box);
  });
}
