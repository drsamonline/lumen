import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/models/edit_recipe.dart';

void main() {
  group('EditRecipe', () {
    test('the empty recipe is an identity', () {
      expect(EditRecipe.empty.isIdentity, isTrue);
      expect(EditRecipe.empty.hasCrop, isFalse);
      expect(EditRecipe.empty.hasColorWork, isFalse);
    });

    test('the identity matrix is the neutral colour filter', () {
      final m = EditRecipe.empty.colorMatrix();
      expect(m.length, 20);
      expect(m[0], 1.0);
      expect(m[6], 1.0);
      expect(m[12], 1.0);
      expect(m[18], 1.0);
      // Everything off-diagonal, including the translation column, is zero.
      const diagonal = <int>{0, 6, 12, 18};
      for (var i = 0; i < 20; i++) {
        if (diagonal.contains(i)) continue;
        expect(m[i], 0.0, reason: 'index $i should be 0');
      }
    });

    test('brightness moves the translation column, not the gain', () {
      final m = const EditRecipe(brightness: 0.5).colorMatrix();
      expect(m[0], 1.0);
      expect(m[4], closeTo(127.5, 0.001));
      expect(m[9], closeTo(127.5, 0.001));
      expect(m[14], closeTo(127.5, 0.001));
    });

    test('contrast scales around mid grey', () {
      final m = const EditRecipe(contrast: 0.5).colorMatrix();
      expect(m[0], closeTo(1.5, 0.0001));
      expect(m[4], closeTo((1 - 1.5) * 127.5, 0.0001));
    });

    test('saturation of -1 makes all three rows identical', () {
      final m = const EditRecipe(saturation: -1).colorMatrix();
      // Every output channel becomes the same luminance weighting, which is
      // exactly what "fully desaturated" means.
      for (var c = 0; c < 3; c++) {
        expect(m[c], closeTo(m[5 + c], 0.0001), reason: 'row 1');
        expect(m[c], closeTo(m[10 + c], 0.0001), reason: 'row 2');
      }
      // And they sum to 1, so a grey pixel stays grey at the same level.
      expect(m[0] + m[1] + m[2], closeTo(1.0, 0.0001));
    });

    test('JSON round-trips every field', () {
      const recipe = EditRecipe(
        rotate: 270,
        flipH: true,
        cropL: 0.1,
        cropT: 0.2,
        cropR: 0.9,
        cropB: 0.8,
        brightness: -0.3,
        contrast: 0.4,
        saturation: 0.25,
        warmth: -0.5,
        vignette: 0.15,
      );
      final restored = EditRecipe.decode(recipe.encode());
      expect(restored.rotate, 270);
      expect(restored.flipH, isTrue);
      expect(restored.cropL, closeTo(0.1, 1e-9));
      expect(restored.cropR, closeTo(0.9, 1e-9));
      expect(restored.brightness, closeTo(-0.3, 1e-9));
      expect(restored.vignette, closeTo(0.15, 1e-9));
    });

    test('garbage decodes to empty rather than throwing', () {
      expect(EditRecipe.decode('not json').isIdentity, isTrue);
      expect(EditRecipe.decode('').isIdentity, isTrue);
      expect(EditRecipe.decode(null).isIdentity, isTrue);
      expect(EditRecipe.decode('[1,2,3]').isIdentity, isTrue);
    });

    test('compose applies b before a', () {
      final a = EditRecipe.compose(
        const EditRecipe(brightness: 0.1).colorMatrix(),
        const EditRecipe(brightness: 0.2).colorMatrix(),
      );
      // Two brightness passes add up in the translation column.
      expect(a[4], closeTo(0.3 * 255, 0.01));
    });
  });
}
