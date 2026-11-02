import 'dart:convert';

/// A non-destructive edit. The original file on disk is never modified —
/// Picasa's core promise, kept.
///
/// Every adjustment is stored as a number so the recipe survives upgrades and
/// can be applied identically in the app, in the LAN gallery, and on export.
class EditRecipe {
  const EditRecipe({
    this.rotate = 0,
    this.flipH = false,
    this.flipV = false,
    this.cropL = 0.0,
    this.cropT = 0.0,
    this.cropR = 1.0,
    this.cropB = 1.0,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.saturation = 0.0,
    this.warmth = 0.0,
    this.vignette = 0.0,
    this.sharpen = 0.0,
  });

  /// Clockwise rotation in degrees. Normalised to 0 / 90 / 180 / 270.
  final int rotate;
  final bool flipH;
  final bool flipV;

  /// Crop rectangle in normalised image coordinates. Default is the full frame.
  final double cropL;
  final double cropT;
  final double cropR;
  final double cropB;

  /// All adjustments are -1.0 .. 1.0, with 0.0 meaning "untouched".
  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;
  final double vignette;
  final double sharpen;

  static const EditRecipe empty = EditRecipe();

  bool get isIdentity =>
      rotate == 0 &&
      !flipH &&
      !flipV &&
      cropL == 0.0 &&
      cropT == 0.0 &&
      cropR == 1.0 &&
      cropB == 1.0 &&
      brightness == 0.0 &&
      contrast == 0.0 &&
      saturation == 0.0 &&
      warmth == 0.0 &&
      vignette == 0.0 &&
      sharpen == 0.0;

  bool get hasCrop => cropL != 0.0 || cropT != 0.0 || cropR != 1.0 || cropB != 1.0;

  bool get hasColorWork =>
      brightness != 0.0 ||
      contrast != 0.0 ||
      saturation != 0.0 ||
      warmth != 0.0 ||
      vignette != 0.0;

  EditRecipe copyWith({
    int? rotate,
    bool? flipH,
    bool? flipV,
    double? cropL,
    double? cropT,
    double? cropR,
    double? cropB,
    double? brightness,
    double? contrast,
    double? saturation,
    double? warmth,
    double? vignette,
    double? sharpen,
  }) {
    return EditRecipe(
      rotate: rotate ?? this.rotate,
      flipH: flipH ?? this.flipH,
      flipV: flipV ?? this.flipV,
      cropL: cropL ?? this.cropL,
      cropT: cropT ?? this.cropT,
      cropR: cropR ?? this.cropR,
      cropB: cropB ?? this.cropB,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      warmth: warmth ?? this.warmth,
      vignette: vignette ?? this.vignette,
      sharpen: sharpen ?? this.sharpen,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'rotate': rotate,
        'flipH': flipH,
        'flipV': flipV,
        'crop': <double>[cropL, cropT, cropR, cropB],
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'warmth': warmth,
        'vignette': vignette,
        'sharpen': sharpen,
      };

  factory EditRecipe.fromJson(Map<String, dynamic> j) {
    final crop = (j['crop'] as List?)?.map((e) => (e as num).toDouble()).toList();
    return EditRecipe(
      rotate: ((j['rotate'] as num?) ?? 0).toInt() % 360,
      flipH: (j['flipH'] as bool?) ?? false,
      flipV: (j['flipV'] as bool?) ?? false,
      cropL: crop != null && crop.length == 4 ? crop[0] : 0.0,
      cropT: crop != null && crop.length == 4 ? crop[1] : 0.0,
      cropR: crop != null && crop.length == 4 ? crop[2] : 1.0,
      cropB: crop != null && crop.length == 4 ? crop[3] : 1.0,
      brightness: ((j['brightness'] as num?) ?? 0).toDouble(),
      contrast: ((j['contrast'] as num?) ?? 0).toDouble(),
      saturation: ((j['saturation'] as num?) ?? 0).toDouble(),
      warmth: ((j['warmth'] as num?) ?? 0).toDouble(),
      vignette: ((j['vignette'] as num?) ?? 0).toDouble(),
      sharpen: ((j['sharpen'] as num?) ?? 0).toDouble(),
    );
  }

  String encode() => jsonEncode(toJson());

  static EditRecipe decode(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return EditRecipe.fromJson(decoded);
      return empty;
    } catch (_) {
      return empty;
    }
  }

  // ---------------------------------------------------------------- matrices

  static List<double> _identity() => <double>[
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0, //
      ];

  /// Compose two 4x5 colour matrices: returns `a` applied after `b`.
  static List<double> compose(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        var s = 0.0;
        for (var k = 0; k < 4; k++) {
          s += a[r * 5 + k] * b[k * 5 + c];
        }
        out[r * 5 + c] = s;
      }
      var t = a[r * 5 + 4];
      for (var k = 0; k < 4; k++) {
        t += a[r * 5 + k] * b[k * 5 + 4];
      }
      out[r * 5 + 4] = t;
    }
    return out;
  }

  static List<double> _saturation(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final sr = (1 - s) * lr;
    final sg = (1 - s) * lg;
    final sb = (1 - s) * lb;
    return <double>[
      sr + s, sg, sb, 0, 0, //
      sr, sg + s, sb, 0, 0, //
      sr, sg, sb + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  static List<double> _contrast(double c) {
    // Pivot around mid-grey (127.5 in Flutter's unnormalised offset space).
    final t = (1 - c) * 127.5;
    return <double>[
      c, 0, 0, 0, t, //
      0, c, 0, 0, t, //
      0, 0, c, 0, t, //
      0, 0, 0, 1, 0, //
    ];
  }

  static List<double> _brightness(double b) {
    final o = b * 255.0;
    return <double>[
      1, 0, 0, 0, o, //
      0, 1, 0, 0, o, //
      0, 0, 1, 0, o, //
      0, 0, 0, 1, 0, //
    ];
  }

  static List<double> _warmth(double w) {
    final r = 1 + 0.28 * w;
    final g = 1 + 0.04 * w;
    final b = 1 - 0.24 * w;
    return <double>[
      r, 0, 0, 0, 0, //
      0, g, 0, 0, 0, //
      0, 0, b, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// The combined 4x5 matrix to hand to `ColorFilter.matrix`.
  List<double> colorMatrix() {
    var m = _identity();
    if (saturation != 0) m = compose(_saturation(1 + saturation.clamp(-0.95, 1.5)), m);
    if (warmth != 0) m = compose(_warmth(warmth.clamp(-1.0, 1.0)), m);
    if (contrast != 0) m = compose(_contrast(1 + contrast.clamp(-0.95, 1.5)), m);
    if (brightness != 0) m = compose(_brightness(brightness.clamp(-1.0, 1.0)), m);
    return m;
  }
}
