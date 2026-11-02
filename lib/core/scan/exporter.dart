import 'dart:io';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../export/metadata_check.dart';
import '../models/edit_recipe.dart';
import '../models/photo.dart';
import '../models/tone_curve.dart';
import 'lut_renderer.dart';
import 'thumbnail_service.dart';

/// What an export produced, and proof of what is in it.
class ExportResult {
  const ExportResult({required this.file, required this.leftover});

  final File file;

  /// Metadata blocks still present in the written bytes. Empty means clean.
  final List<String> leftover;

  bool get clean => leftover.isEmpty;

  String get report =>
      clean ? 'checked: nothing left' : 'still contains ${leftover.join(', ')}';
}

/// Bakes an [EditRecipe] into pixels.
///
/// The same render is used for the exported file and for the regenerated grid
/// thumbnail, so the tile, the viewer and the exported PNG cannot disagree.
/// The original is never touched.
class Exporter {
  static Future<ExportResult?> exportEdited(Photo photo, EditRecipe recipe) async {
    final rendered = await render(
      photo,
      recipe,
      maxSourceWidth: 6000,
      maxOutputWidth: null,
    );
    if (rendered == null) return null;

    try {
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      if (data == null) return null;

      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final target = await _targetFile(photo);
      await target.writeAsBytes(bytes, flush: true);

      // The canvas re-encode cannot carry EXIF, but "cannot" is a claim. Read
      // the bytes back and report what is actually in the file.
      final leftover = await MetadataCheck.scan(target);
      return ExportResult(file: target, leftover: leftover);
    } catch (_) {
      rendered.dispose();
      return null;
    }
  }

  /// Regenerates the cached grid thumbnail so it reflects the recipe.
  ///
  /// Without this the grid shows the unedited photo while the viewer shows the
  /// edit — the inconsistency every photo app gets wrong. Rendering at
  /// [ThumbnailService.thumbWidth] keeps it cheap: one decode and one draw per
  /// save, not per scroll.
  static Future<bool> regenerateThumbnail(Photo photo, EditRecipe recipe) async {
    final rendered = await render(
      photo,
      recipe,
      maxSourceWidth: ThumbnailService.thumbWidth,
      maxOutputWidth: ThumbnailService.thumbWidth,
    );
    if (rendered == null) return false;

    try {
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      if (data == null) return false;

      final file = await AppPaths.thumbFile(photo.id);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: false,
      );
      return true;
    } catch (_) {
      rendered.dispose();
      return false;
    }
  }

  /// Decode, apply the curve, then draw the crop / flip / rotate / colour stack.
  ///
  /// The curve is applied to the source pixels *before* the colour matrix, so
  /// the order is the same here, in the viewer and in the thumbnail. Getting
  /// that order inconsistent between two code paths is the usual way a photo
  /// editor ends up with a preview that does not match its export.
  static Future<ui.Image?> render(
    Photo photo,
    EditRecipe recipe, {
    required int maxSourceWidth,
    int? maxOutputWidth,
  }) async {
    final decoded = await ThumbnailService.decodeBounded(
      photo.path,
      maxWidth: maxSourceWidth,
    );
    if (decoded == null) return null;

    var source = decoded;
    if (recipe.hasCurve) {
      source = await LutRenderer.applyCurve(source, ToneCurve(recipe.curve));
    }

    try {
      final srcW = source.width.toDouble();
      final srcH = source.height.toDouble();

      final cropL = (recipe.cropL * srcW).roundToDouble();
      final cropT = (recipe.cropT * srcH).roundToDouble();
      final cropW = ((recipe.cropR - recipe.cropL) * srcW).roundToDouble();
      final cropH = ((recipe.cropB - recipe.cropT) * srcH).roundToDouble();

      final safeW = cropW <= 0 ? srcW : cropW;
      final safeH = cropH <= 0 ? srcH : cropH;

      final quarter = (recipe.rotate ~/ 90) % 4;
      final swapped = quarter == 1 || quarter == 3;

      var outW = swapped ? safeH : safeW;
      var outH = swapped ? safeW : safeH;

      var scale = 1.0;
      if (maxOutputWidth != null && outW > maxOutputWidth) {
        scale = maxOutputWidth / outW;
        outW *= scale;
        outH *= scale;
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final paint = Paint()
        ..filterQuality = FilterQuality.high
        ..colorFilter = recipe.hasColorWork
            ? ColorFilter.matrix(recipe.colorMatrix())
            : null;

      // Move to the output centre, apply rotation and flips, then draw the
      // source rect centred on the origin.
      canvas.translate(outW / 2, outH / 2);
      canvas.rotate(quarter * 3.141592653589793 / 2);
      canvas.scale(recipe.flipH ? -1.0 : 1.0, recipe.flipV ? -1.0 : 1.0);

      final dst = Rect.fromCenter(
        center: Offset.zero,
        width: safeW * scale,
        height: safeH * scale,
      );
      final src = Rect.fromLTWH(
        cropL.clamp(0.0, srcW - 1),
        cropT.clamp(0.0, srcH - 1),
        safeW,
        safeH,
      );

      canvas.drawImageRect(source, src, dst, paint);

      final picture = recorder.endRecording();
      final result = await picture.toImage(
        outW.round().clamp(1, 20000),
        outH.round().clamp(1, 20000),
      );
      picture.dispose();
      source.dispose();
      return result;
    } catch (_) {
      source.dispose();
      return null;
    }
  }

  static Future<File> _targetFile(Photo photo) async {
    final base = p.basenameWithoutExtension(photo.fileName);
    final name = '${base}_lumen.png';
    final sibling = File(p.join(photo.folder, name));
    try {
      // Probe with a throwaway file so we never truncate a previous export.
      final probe = File(p.join(photo.folder, '.lumen_write_probe'));
      await probe.writeAsBytes(<int>[0], flush: true);
      await probe.delete();
      return sibling;
    } catch (_) {
      return File(p.join(AppPaths.exports.path, name));
    }
  }
}
