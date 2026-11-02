import 'dart:io';
import 'dart:ui' as ui;

/// How a format is reachable right now.
enum FormatAvailability {
  /// Decoded in-process by the Flutter engine. Always works, no setup.
  builtIn,

  /// Decoded by an open-source library that is installed on this machine.
  ready,

  /// A plugin exists for this format but its library is not installed.
  needsInstall,
}

/// One decodable image format.
///
/// Lumen does not hardcode a list of extensions. Every format is a plugin, and
/// a plugin knows three things: which extensions it claims, which open-source
/// library does the actual decoding, and whether that library is reachable on
/// this machine.
///
/// Adding a format means adding a plugin — no changes to the scanner, the
/// thumbnailer, the viewer or the LAN server, all of which ask the registry
/// instead of testing a suffix.
abstract class ImageFormatPlugin {
  /// Stable identifier, used in settings and logs.
  String get id;

  /// Human name for the settings list.
  String get displayName;

  /// Lower-case extensions, without the dot.
  List<String> get extensions;

  /// The open-source project that does the decoding, for the credits UI.
  String get poweredBy;

  /// What the user must install for this to work, or null when built in.
  String? get requirement;

  /// Cheap probe, cached by the registry.
  Future<FormatAvailability> probe();

  /// Decode to a [ui.Image], optionally downsampled. Null means "could not".
  Future<ui.Image?> decode(File file, {int? targetWidth});

  /// True when the bytes this plugin produces can be handed straight to a
  /// browser. The LAN server uses this to decide whether to transcode.
  bool get browserSafe;
}

/// A snapshot of one plugin's state, for the settings screen.
class FormatStatus {
  const FormatStatus({
    required this.plugin,
    required this.availability,
  });

  final ImageFormatPlugin plugin;
  final FormatAvailability availability;

  /// Extensions, capped. The RAW plugin claims eighteen; listing them all turns
  /// a settings row into a wall of text.
  String get extensionsLabel {
    const shown = 6;
    final list = plugin.extensions.map((e) => e.toUpperCase()).toList();
    if (list.length <= shown) return list.join(', ');
    final rest = list.length - shown;
    return '${list.take(shown).join(', ')} +$rest more';
  }
}
