import 'dart:io';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../models/edit_recipe.dart';
import '../models/photo.dart';
import 'thumbnail_service.dart';

/// Bakes an [EditRecipe] into a real image file.
///
/// The original is never touched — this always writes a sibling file next to
/// the source (or into the app's exports folder if that is not writable).
class Exporter {
  static Future<File?> exportEdited(Photo photo, EditRecipe recipe) async {
    final source = await ThumbnailService.decodeBounded(photo.path, maxWidth: 6000);
    if (source == null) return null;

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

      final outW = swapped ? safeH : safeW;
      final outH = swapped ? safeW : safeH;

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
        width: safeW,
        height: safeH,
      );
      final src = Rect.fromLTWH(
        cropL.clamp(0.0, srcW - 1),
        cropT.clamp(0.0, srcH - 1),
        safeW,
        safeH,
      );

      canvas.drawImageRect(source, src, dst, paint);

      final picture = recorder.endRecording();
      final rendered = await picture.toImage(outW.round(), outH.round());
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      rendered.dispose();
      source.dispose();

      if (data == null) return null;
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      final target = await _targetFile(photo);
      await target.writeAsBytes(bytes, flush: true);
      return target;
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
