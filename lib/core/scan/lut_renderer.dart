import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/tone_curve.dart';

/// Applies a tone-curve LUT to a decoded image.
///
/// This runs on the CPU, once per render, rather than in a fragment shader.
/// The trade is a few tens of milliseconds per full-size preview against the
/// risk of a shader that compiles but draws nothing on some driver. For a photo
/// viewer, where a frame is rendered when a photo opens rather than sixty times
/// a second, the predictable option wins.
class LutRenderer {
  static Future<ui.Image?> apply(ui.Image source, Uint8List lut) async {
    try {
      final data = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;

      // toByteData hands back a view over the engine buffer; copy before
      // mutating so the source image is not corrupted.
      final pixels = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      applyLutToRgba(pixels, lut);

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        source.width,
        source.height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      return await completer.future;
    } catch (_) {
      return null;
    }
  }

  /// Applies a curve, disposing the source when a new image was produced.
  ///
  /// Never returns null: a failed LUT pass hands back the original image, so a
  /// caller never has to reason about a half-applied edit.
  static Future<ui.Image> applyCurve(
    ui.Image source,
    ToneCurve curve, {
    bool disposeSource = true,
  }) async {
    final result = await apply(source, curve.buildLut());
    if (result == null) return source;
    if (disposeSource) source.dispose();
    return result;
  }
}
