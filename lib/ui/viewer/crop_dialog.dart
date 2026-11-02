import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/models/crop_math.dart';
import '../../core/models/edit_recipe.dart';
import '../widgets/edited_image.dart';

/// Aspect presets, as pixel width / height. `null` means free-form.
class CropPreset {
  const CropPreset(this.label, this.aspect);
  final String label;
  final double? aspect;
}

const List<CropPreset> kCropPresets = <CropPreset>[
  CropPreset('Free', null),
  CropPreset('1:1', 1.0),
  CropPreset('4:3', 4 / 3),
  CropPreset('3:4', 3 / 4),
  CropPreset('3:2', 3 / 2),
  CropPreset('16:9', 16 / 9),
];

/// Full-screen crop tool. Returns the chosen rectangle in normalised
/// coordinates, or null if the user backed out.
Future<Rect?> showCropDialog(
  BuildContext context, {
  required File file,
  required double imageAspect,
  required EditRecipe recipe,
  ui.Image? decoded,
}) {
  return Navigator.of(context).push<Rect>(
    MaterialPageRoute<Rect>(
      fullscreenDialog: true,
      builder: (_) => CropDialog(
        file: file,
        imageAspect: imageAspect,
        recipe: recipe,
        decoded: decoded,
      ),
    ),
  );
}

class CropDialog extends StatefulWidget {
  const CropDialog({
    super.key,
    required this.file,
    required this.imageAspect,
    required this.recipe,
    this.decoded,
  });

  final File file;
  final double imageAspect;
  final EditRecipe recipe;
  final ui.Image? decoded;

  @override
  State<CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<CropDialog> {
  late Rect _rect = CropMath.fromRecipe(
    widget.recipe.cropL,
    widget.recipe.cropT,
    widget.recipe.cropR,
    widget.recipe.cropB,
  );
  double? _aspect;
  Size _box = Size.zero;

  void _applyPreset(CropPreset preset) {
    setState(() {
      _aspect = preset.aspect;
      if (preset.aspect == null) return;
      _rect = _box == Size.zero
          ? _rect
          : CropMath.reaspect(_rect, aspect: preset.aspect!, box: _box);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Crop', style: TextStyle(fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, _rect),
            child: const Text('Apply'),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final box = _fit(constraints.biggest, widget.imageAspect);
                  _box = box;
                  return SizedBox(
                    width: box.width,
                    height: box.height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        EditedImage(
                          file: widget.file,
                          recipe: EditRecipe.empty,
                          fit: BoxFit.contain,
                          cacheWidth: 1600,
                          decoded: widget.decoded,
                        ),
                        IgnorePointer(
                          child: CustomPaint(painter: _CropPainter(_rect)),
                        ),
                        for (var corner = 0; corner < 4; corner++)
                          _handle(corner, box),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          _PresetBar(
            selected: _aspect,
            onSelected: _applyPreset,
            onReset: () => setState(() {
              _rect = CropMath.full;
              _aspect = null;
            }),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static Size _fit(Size available, double aspect) {
    if (available.width <= 0 || available.height <= 0) return Size.zero;
    var width = available.width;
    var height = width / aspect;
    if (height > available.height) {
      height = available.height;
      width = height * aspect;
    }
    return Size(width, height);
  }

  Widget _handle(int corner, Size box) {
    final isLeft = corner == CropMath.topLeft || corner == CropMath.bottomLeft;
    final isTop = corner == CropMath.topLeft || corner == CropMath.topRight;
    const size = 34.0;

    final x = (isLeft ? _rect.left : _rect.right) * box.width;
    final y = (isTop ? _rect.top : _rect.bottom) * box.height;

    return Positioned(
      left: x - size / 2,
      top: y - size / 2,
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          if (box.width <= 0 || box.height <= 0) return;
          final delta = Offset(
            details.delta.dx / box.width,
            details.delta.dy / box.height,
          );
          setState(() {
            _rect = CropMath.dragCorner(
              rect: _rect,
              corner: corner,
              delta: delta,
              box: box,
              aspect: _aspect,
            );
          });
        },
        child: Center(
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black54, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetBar extends StatelessWidget {
  const _PresetBar({
    required this.selected,
    required this.onSelected,
    required this.onReset,
  });

  final double? selected;
  final ValueChanged<CropPreset> onSelected;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: <Widget>[
          for (final preset in kCropPresets)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: ChoiceChip(
                label: Text(preset.label),
                selected: selected == preset.aspect,
                onSelected: (_) => onSelected(preset),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: ActionChip(
              avatar: const Icon(Icons.restart_alt, size: 16),
              label: const Text('Full'),
              onPressed: onReset,
            ),
          ),
        ],
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final crop = Rect.fromLTRB(
      rect.left * size.width,
      rect.top * size.height,
      rect.right * size.width,
      rect.bottom * size.height,
    );

    // Dim everything outside the crop.
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.62);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, crop.top), dim);
    canvas.drawRect(
      Rect.fromLTWH(0, crop.bottom, size.width, size.height - crop.bottom),
      dim,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, crop.top, crop.left, crop.height),
      dim,
    );
    canvas.drawRect(
      Rect.fromLTWH(crop.right, crop.top, size.width - crop.right, crop.height),
      dim,
    );

    // Rule-of-thirds guides.
    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final dx = crop.left + crop.width * i / 3;
      final dy = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(dx, crop.top), Offset(dx, crop.bottom), guide);
      canvas.drawLine(Offset(crop.left, dy), Offset(crop.right, dy), guide);
    }

    canvas.drawRect(
      crop,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) => oldDelegate.rect != rect;
}
