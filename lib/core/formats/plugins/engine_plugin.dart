import 'dart:io';
import 'dart:ui' as ui;

import '../image_format.dart';

/// The formats the Flutter engine decodes natively, on every platform, with no
/// setup. This is the fast path and it always wins when it can.
///
/// Decoding passes a target width straight to the engine, which downsamples
/// during decode rather than after — the single biggest reason the grid stays
/// responsive on a phone full of 12 MP photos.
class EngineImagePlugin implements ImageFormatPlugin {
  const EngineImagePlugin();

  @override
  String get id => 'engine';

  @override
  String get displayName => 'Built-in';

  @override
  List<String> get extensions => const <String>[
        'jpg', 'jpeg', 'jfif', 'png', 'webp', 'gif', 'bmp', 'wbmp',
      ];

  @override
  String get poweredBy => 'Skia / Impeller (Flutter engine)';

  @override
  String? get requirement => null;

  @override
  bool get browserSafe => true;

  @override
  Future<FormatAvailability> probe() async => FormatAvailability.builtIn;

  @override
  Future<ui.Image?> decode(File file, {int? targetWidth}) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }
}
