import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/models/edit_recipe.dart';
import 'package:lumen/core/models/tone_curve.dart';

void main() {
  group('linear curve', () {
    test('produces an identity table', () {
      final lut = ToneCurve.linear.buildLut();
      expect(lut.length, 256);
      for (var i = 0; i < 256; i++) {
        expect(lut[i], i, reason: 'index $i');
      }
    });

    test('reports itself as identity', () {
      expect(ToneCurve.linear.isIdentity, isTrue);
    });
  });

  group('LUT generation', () {
    test('a curve with too few points falls back to linear', () {
      final lut = const ToneCurve(<CurvePoint>[CurvePoint(0.5, 0.2)]).buildLut();
      for (var i = 0; i < 256; i++) {
        expect(lut[i], i);
      }
    });

    test('presets are monotone and in range', () {
      for (final preset in CurvePreset.all) {
        final lut = ToneCurve(preset.points).buildLut();
        for (var i = 1; i < lut.length; i++) {
          expect(lut[i], greaterThanOrEqualTo(lut[i - 1]),
              reason: '${preset.name} dips at $i');
        }
        expect(lut.first, greaterThanOrEqualTo(0));
        expect(lut.last, lessThanOrEqualTo(255));
      }
    });

    test('lift shadows raises the black point', () {
      final lut = ToneCurve(CurvePreset.all
              .firstWhere((p) => p.name == 'Lift shadows')
              .points)
          .buildLut();
      expect(lut[0], closeTo(18, 2)); // 0.07 * 255
      expect(lut[0], greaterThan(0));
    });

    test('matte crushes neither end', () {
      final lut = ToneCurve(
        CurvePreset.all.firstWhere((p) => p.name == 'Matte').points,
      ).buildLut();
      expect(lut[0], greaterThan(10));
      expect(lut[255], lessThan(250));
    });

    test('a steep curve does not overshoot its control points', () {
      // Monotone cubic exists to stop exactly this: a plain spline would bulge
      // past 1.0 between the two right-hand points.
      final lut = const ToneCurve(<CurvePoint>[
        CurvePoint(0, 0),
        CurvePoint(0.5, 1),
        CurvePoint(1, 1),
      ]).buildLut();
      for (var i = 0; i < lut.length; i++) {
        expect(lut[i], lessThanOrEqualTo(255));
      }
      expect(lut[255], 255);
      // Monotone: never decreases.
      for (var i = 1; i < lut.length; i++) {
        expect(lut[i], greaterThanOrEqualTo(lut[i - 1]));
      }
    });

    test('isIdentity is false for a real curve', () {
      expect(ToneCurve(CurvePreset.all[1].points).isIdentity, isFalse);
    });

    test('duplicate x values are collapsed', () {
      final curve = const ToneCurve(<CurvePoint>[
        CurvePoint(0, 0),
        CurvePoint(0.5, 0.2),
        CurvePoint(0.5, 0.8),
        CurvePoint(1, 1),
      ]);
      expect(curve.normalised.length, 3);
    });
  });

  group('applyLutToRgba', () {
    test('an identity LUT changes nothing', () {
      final rgba = Uint8List.fromList(<int>[10, 20, 30, 255, 200, 100, 50, 128]);
      final before = Uint8List.fromList(rgba);
      applyLutToRgba(rgba, ToneCurve.linear.buildLut());
      expect(rgba, before);
    });

    test('an inverting LUT flips the channels and leaves alpha alone', () {
      final inverted = Uint8List.fromList(
        List<int>.generate(256, (i) => 255 - i),
      );
      final rgba = Uint8List.fromList(<int>[0, 255, 128, 77]);
      applyLutToRgba(rgba, inverted);
      expect(rgba[0], 255);
      expect(rgba[1], 0);
      expect(rgba[2], 127);
      expect(rgba[3], 77, reason: 'alpha must be untouched');
    });
  });

  group('serialisation', () {
    test('round-trips through JSON', () {
      final curve = ToneCurve(CurvePreset.all[2].points);
      final restored = ToneCurve.fromJson(curve.toJson());
      expect(restored.points.length, curve.points.length);
      for (var i = 0; i < curve.points.length; i++) {
        expect(restored.points[i], curve.points[i]);
      }
    });

    test('garbage decodes to linear rather than throwing', () {
      expect(ToneCurve.fromJson(null).isIdentity, isTrue);
      expect(ToneCurve.fromJson('nonsense').isIdentity, isTrue);
      expect(ToneCurve.fromJson(<dynamic>[]).isIdentity, isTrue);
      expect(ToneCurve.fromJson(<dynamic>[1, 2, 3]).isIdentity, isTrue);
    });
  });

  group('EditRecipe integration', () {
    test('a recipe with a curve is not an identity', () {
      final recipe = EditRecipe(curve: CurvePreset.all[1].points);
      expect(recipe.hasCurve, isTrue);
      expect(recipe.isIdentity, isFalse);
    });

    test('a linear curve is still an identity', () {
      const recipe = EditRecipe(curve: <CurvePoint>[
        CurvePoint(0, 0),
        CurvePoint(1, 1),
      ]);
      expect(recipe.hasCurve, isTrue);
      expect(recipe.isIdentity, isTrue);
    });

    test('the curve survives an encode and decode', () {
      final recipe = EditRecipe(curve: CurvePreset.all[3].points);
      final restored = EditRecipe.decode(recipe.encode());
      expect(restored.curve.length, recipe.curve.length);
      expect(restored.curve.first, recipe.curve.first);
      expect(restored.curve.last, recipe.curve.last);
    });

    test('a recipe without a curve stays small in JSON', () {
      const recipe = EditRecipe(brightness: 0.2);
      expect(recipe.encode().contains('curve'), isFalse);
    });

    test('withoutCurve strips only the curve', () {
      final recipe = EditRecipe(
        brightness: 0.3,
        curve: CurvePreset.all[1].points,
      );
      final stripped = recipe.withoutCurve;
      expect(stripped.hasCurve, isFalse);
      expect(stripped.brightness, closeTo(0.3, 1e-9));
      expect(stripped.encode().contains('curve'), isFalse);
    });
  });
}
