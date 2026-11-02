import 'package:flutter/material.dart';

import '../../core/models/tone_curve.dart';

/// Opens the tone-curve editor. Returns the chosen control points, or null if
/// the user backed out.
Future<List<CurvePoint>?> showCurveEditor(
  BuildContext context, {
  required List<CurvePoint> initial,
}) {
  return Navigator.of(context).push<List<CurvePoint>>(
    MaterialPageRoute<List<CurvePoint>>(
      fullscreenDialog: true,
      builder: (_) => CurveEditorScreen(initial: initial),
    ),
  );
}

class CurveEditorScreen extends StatefulWidget {
  const CurveEditorScreen({super.key, required this.initial});

  final List<CurvePoint> initial;

  @override
  State<CurveEditorScreen> createState() => _CurveEditorScreenState();
}

class _CurveEditorScreenState extends State<CurveEditorScreen> {
  late List<CurvePoint> _points = widget.initial.length >= 2
      ? List<CurvePoint>.from(widget.initial)
      : List<CurvePoint>.from(ToneCurve.linear.points);

  int? _dragIndex;

  static const double _hitRadius = 26;

  ToneCurve get _curve => ToneCurve(_points);

  /// Points are stored bottom-left origin; the canvas is top-left, so y flips.
  Offset _toLocal(CurvePoint point, Size size) =>
      Offset(point.x * size.width, (1 - point.y) * size.height);

  CurvePoint _toNormalised(Offset local, Size size) => CurvePoint(
        (local.dx / size.width).clamp(0.0, 1.0),
        (1 - local.dy / size.height).clamp(0.0, 1.0),
      );

  int? _nearest(Offset local, Size size) {
    var best = -1;
    var bestDistance = _hitRadius;
    for (var i = 0; i < _points.length; i++) {
      final distance = (_toLocal(_points[i], size) - local).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best < 0 ? null : best;
  }

  void _beginDrag(Offset local, Size size) {
    setState(() => _dragIndex = _nearest(local, size));
  }

  void _drag(Offset local, Size size) {
    final index = _dragIndex;
    if (index == null) return;
    final raw = _toNormalised(local, size);
    final isFirst = index == 0;
    final isLast = index == _points.length - 1;

    setState(() {
      if (isFirst) {
        // The endpoints keep their x so the curve always spans the full range.
        _points[index] = _points[index].copyWith(y: raw.y);
      } else if (isLast) {
        _points[index] = _points[index].copyWith(y: raw.y);
      } else {
        final left = _points[index - 1].x + 0.01;
        final right = _points[index + 1].x - 0.01;
        _points[index] = CurvePoint(raw.x.clamp(left, right), raw.y);
      }
    });
  }

  void _addPoint(Offset local, Size size) {
    final point = _toNormalised(local, size);
    setState(() {
      _points.add(point);
      _points = ToneCurve(_points).normalised;
    });
  }

  void _removePoint(int index) {
    if (index == 0 || index == _points.length - 1) return;
    setState(() => _points.removeAt(index));
  }

  void _applyPreset(CurvePreset preset) {
    setState(() => _points = List<CurvePoint>.from(preset.points));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Curves', style: TextStyle(fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, _points),
            child: const Text('Apply'),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(constraints.maxWidth, constraints.maxHeight);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) => _beginDrag(d.localPosition, size),
                        onPanUpdate: (d) => _drag(d.localPosition, size),
                        onPanEnd: (_) => setState(() => _dragIndex = null),
                        onTapUp: (d) {
                          if (_nearest(d.localPosition, size) == null) {
                            _addPoint(d.localPosition, size);
                          }
                        },
                        onLongPressStart: (d) {
                          final index = _nearest(d.localPosition, size);
                          if (index != null) _removePoint(index);
                        },
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: CustomPaint(
                            painter: _CurvePainter(
                              points: _points,
                              lut: _curve.buildLut(),
                              grid: scheme.outlineVariant,
                              curveColor: scheme.primary,
                              diagonal: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                            ),
                            size: size,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Drag a point to shape the curve. Tap to add one, long-press to '
              'remove. Black is bottom-left, white is top-right.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: <Widget>[
                for (final preset in CurvePreset.all)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ActionChip(
                      label: Text(preset.name),
                      onPressed: () => _applyPreset(preset),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.points,
    required this.lut,
    required this.grid,
    required this.curveColor,
    required this.diagonal,
  });

  final List<CurvePoint> points;
  final List<int> lut;
  final Color grid;
  final Color curveColor;
  final Color diagonal;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      Paint()
        ..color = diagonal
        ..strokeWidth = 1,
    );

    // The curve itself is drawn from the LUT, so what the editor shows is
    // exactly what the renderer will use.
    final path = Path();
    for (var i = 0; i < lut.length; i++) {
      final x = size.width * i / (lut.length - 1);
      final y = size.height * (1 - lut[i] / 255);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = curveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    for (final point in points) {
      final offset = Offset(
        point.x * size.width,
        (1 - point.y) * size.height,
      );
      canvas.drawCircle(offset, 7, Paint()..color = curveColor);
      canvas.drawCircle(
        offset,
        7,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_CurvePainter oldDelegate) {
    // Always repaint: the painter is only constructed when the editor rebuilds,
    // which happens on a drag. Comparing the point list would be wrong anyway,
    // because it is mutated in place rather than replaced.
    return true;
  }
}
