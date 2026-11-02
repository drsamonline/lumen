import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Disposes a decoded image after the current frame has been painted.
///
/// A `RawImage` that is still mounted during a rebuild can reference the old
/// `ui.Image` for one more frame. Disposing it synchronously — which is the
/// obvious thing to write — throws "Cannot draw a disposed image" instead of
/// showing the new photo. Deferring by a frame is the cheap correct fix.
void deferImageDisposal(ui.Image? image) {
  if (image == null) return;
  try {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        image.dispose();
      } catch (_) {
        // Already disposed, or the engine is shutting down.
      }
    });
  } catch (_) {
    // No binding (tests tearing down): disposing now is better than leaking.
    try {
      image.dispose();
    } catch (_) {}
  }
}
