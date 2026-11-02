import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/models/edit_recipe.dart';

/// Renders an image file with a non-destructive [EditRecipe] applied.
///
/// The same widget is used at thumbnail size in the grid and at full size in
/// the viewer, so what you see in the grid is exactly what you get in the
/// viewer — a mismatch there is the classic photo-app bug.
class EditedImage extends StatelessWidget {
  const EditedImage({
    super.key,
    required this.file,
    this.recipe = EditRecipe.empty,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.decoded,
  });

  final File file;
  final EditRecipe recipe;
  final BoxFit fit;
  final int? cacheWidth;

  /// Set for formats the engine cannot read directly (HEIC, RAW, TIFF). The
  /// caller decodes through the format registry and hands the pixels in, so the
  /// same edit stack applies to every format.
  final ui.Image? decoded;

  @override
  Widget build(BuildContext context) {
    Widget child = decoded != null
        ? RawImage(
            image: decoded,
            fit: fit,
            filterQuality: FilterQuality.medium,
          )
        : Image.file(
            file,
            fit: fit,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stack) => const _BrokenTile(),
          );

    if (recipe.hasColorWork) {
      child = ColorFiltered(
        colorFilter: ColorFilter.matrix(recipe.colorMatrix()),
        child: child,
      );
    }

    if (recipe.flipH || recipe.flipV) {
      child = Transform.flip(flipX: recipe.flipH, flipY: recipe.flipV, child: child);
    }

    if (recipe.hasCrop) {
      final w = (recipe.cropR - recipe.cropL).clamp(0.05, 1.0);
      final h = (recipe.cropB - recipe.cropT).clamp(0.05, 1.0);
      final cx = ((recipe.cropL + recipe.cropR) / 2) * 2 - 1;
      final cy = ((recipe.cropT + recipe.cropB) / 2) * 2 - 1;
      child = ClipRect(
        child: Transform.scale(
          scaleX: 1 / w,
          scaleY: 1 / h,
          alignment: Alignment(cx, cy),
          child: child,
        ),
      );
    }

    if (recipe.rotate != 0) {
      child = RotatedBox(quarterTurns: (recipe.rotate ~/ 90) % 4, child: child);
    }

    return child;
  }
}

class _BrokenTile extends StatelessWidget {
  const _BrokenTile();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
