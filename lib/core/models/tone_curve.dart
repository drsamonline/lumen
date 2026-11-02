import 'dart:math' as math;
import 'dart:typed_data';

/// One control point on the tone curve, in normalised 0..1 space.
class CurvePoint {
  const CurvePoint(this.x, this.y);

  final double x;
  final double y;

  CurvePoint copyWith({double? x, double? y}) =>
      CurvePoint(x ?? this.x, y ?? this.y);

  Map<String, dynamic> toJson() => <String, dynamic>{'x': x, 'y': y};

  factory CurvePoint.fromJson(Map<String, dynamic> json) => CurvePoint(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CurvePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'CurvePoint(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

/// A tone curve, evaluated to a 256-entry lookup table.
///
/// Interpolation is monotone cubic (Fritsch-Carlson) rather than a plain
/// spline. A plain spline overshoots between control points, which on a tone
/// curve shows up as a bright ring around a dark edge — the classic reason
/// hand-rolled curve tools look wrong.
///
/// The LUT is applied on the CPU rather than through a fragment shader. That
/// keeps the same numbers in the grid thumbnail, the viewer and the exported
/// file, needs no asset pipeline, and cannot produce a blank frame at runtime
/// if a driver disagrees with the shader.
class ToneCurve {
  const ToneCurve(this.points);

  final List<CurvePoint> points;

  static const ToneCurve linear = ToneCurve(<CurvePoint>[
    CurvePoint(0, 0),
    CurvePoint(1, 1),
  ]);

  static const int lutSize = 256;

  bool get isUsable => points.length >= 2;

  /// True when the curve is the straight diagonal within a rounding step.
  bool get isIdentity {
    if (!isUsable) return true;
    final table = buildLut();
    for (var i = 0; i < lutSize; i++) {
      if ((table[i] - i).abs() > 1) return false;
    }
    return true;
  }

  /// Points sorted left to right, with duplicate x values dropped.
  List<CurvePoint> get normalised {
    final sorted = List<CurvePoint>.from(points)
      ..sort((a, b) => a.x.compareTo(b.x));
    final out = <CurvePoint>[];
    for (final point in sorted) {
      final x = point.x.clamp(0.0, 1.0);
      final y = point.y.clamp(0.0, 1.0);
      if (out.isNotEmpty && (x - out.last.x).abs() < 1e-4) {
        out[out.length - 1] = CurvePoint(x, y);
        continue;
      }
      out.add(CurvePoint(x, y));
    }
    return out;
  }

  Uint8List buildLut({int size = lutSize}) {
    final lut = Uint8List(size);
    final pts = normalised;

    if (pts.length < 2) {
      for (var i = 0; i < size; i++) {
        lut[i] = (i * 255 / (size - 1)).round();
      }
      return lut;
    }

    final n = pts.length;
    final xs = List<double>.generate(n, (i) => pts[i].x);
    final ys = List<double>.generate(n, (i) => pts[i].y);

    // Secant slopes.
    final delta = List<double>.filled(n - 1, 0);
    for (var i = 0; i < n - 1; i++) {
      final dx = xs[i + 1] - xs[i];
      delta[i] = dx.abs() < 1e-9 ? 0 : (ys[i + 1] - ys[i]) / dx;
    }

    // Initial tangents: average of neighbouring secants, flat at sign changes.
    final tangent = List<double>.filled(n, 0);
    tangent[0] = delta[0];
    tangent[n - 1] = delta[n - 2];
    for (var i = 1; i < n - 1; i++) {
      tangent[i] = delta[i - 1] * delta[i] <= 0
          ? 0
          : (delta[i - 1] + delta[i]) / 2;
    }

    // Fritsch-Carlson limiter: this is what removes the overshoot.
    for (var i = 0; i < n - 1; i++) {
      if (delta[i].abs() < 1e-12) {
        tangent[i] = 0;
        tangent[i + 1] = 0;
        continue;
      }
      final a = tangent[i] / delta[i];
      final b = tangent[i + 1] / delta[i];
      final s = a * a + b * b;
      if (s > 9) {
        final tau = 3 / math.sqrt(s);
        tangent[i] = tau * a * delta[i];
        tangent[i + 1] = tau * b * delta[i];
      }
    }

    for (var i = 0; i < size; i++) {
      final x = i / (size - 1);
      var k = 0;
      while (k < n - 2 && x > xs[k + 1]) {
        k++;
      }
      final h = xs[k + 1] - xs[k];
      double y;
      if (h.abs() < 1e-9) {
        y = ys[k];
      } else {
        final t = ((x - xs[k]) / h).clamp(0.0, 1.0);
        final t2 = t * t;
        final t3 = t2 * t;
        final h00 = 2 * t3 - 3 * t2 + 1;
        final h10 = t3 - 2 * t2 + t;
        final h01 = -2 * t3 + 3 * t2;
        final h11 = t3 - t2;
        y = h00 * ys[k] + h10 * h * tangent[k] + h01 * ys[k + 1] + h11 * h * tangent[k + 1];
      }
      lut[i] = (y.clamp(0.0, 1.0) * 255).round();
    }
    return lut;
  }

  List<Map<String, dynamic>> toJson() =>
      points.map((p) => p.toJson()).toList(growable: false);

  static ToneCurve fromJson(Object? raw) {
    if (raw is! List) return linear;
    final pts = <CurvePoint>[];
    for (final entry in raw) {
      if (entry is Map) {
        final x = entry['x'];
        final y = entry['y'];
        if (x is num && y is num) {
          pts.add(CurvePoint(x.toDouble(), y.toDouble()));
        }
      }
    }
    return pts.length >= 2 ? ToneCurve(pts) : linear;
  }

}

/// Applies a LUT to a raw RGBA8888 buffer in place.
void applyLutToRgba(Uint8List rgba, Uint8List lut) {
  for (var i = 0; i < rgba.length; i += 4) {
    rgba[i] = lut[rgba[i]];
    rgba[i + 1] = lut[rgba[i + 1]];
    rgba[i + 2] = lut[rgba[i + 2]];
  }
}

/// Named starting points for the curve tool.
class CurvePreset {
  const CurvePreset(this.name, this.points);
  final String name;
  final List<CurvePoint> points;

  static const List<CurvePreset> all = <CurvePreset>[
    CurvePreset('Linear', <CurvePoint>[CurvePoint(0, 0), CurvePoint(1, 1)]),
    CurvePreset('Medium contrast', <CurvePoint>[
      CurvePoint(0, 0),
      CurvePoint(0.25, 0.20),
      CurvePoint(0.75, 0.80),
      CurvePoint(1, 1),
    ]),
    CurvePreset('Strong contrast', <CurvePoint>[
      CurvePoint(0, 0),
      CurvePoint(0.25, 0.13),
      CurvePoint(0.75, 0.88),
      CurvePoint(1, 1),
    ]),
    CurvePreset('Lift shadows', <CurvePoint>[
      CurvePoint(0, 0.07),
      CurvePoint(0.35, 0.44),
      CurvePoint(1, 1),
    ]),
    CurvePreset('Matte', <CurvePoint>[
      CurvePoint(0, 0.09),
      CurvePoint(0.5, 0.50),
      CurvePoint(0.92, 0.90),
      CurvePoint(1, 0.95),
    ]),
    CurvePreset('Bright', <CurvePoint>[
      CurvePoint(0, 0.02),
      CurvePoint(0.3, 0.42),
      CurvePoint(1, 1),
    ]),
  ];
}
