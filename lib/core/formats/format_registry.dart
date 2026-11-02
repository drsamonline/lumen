import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import 'image_format.dart';
import 'plugins/engine_plugin.dart';
import 'plugins/external_decoder_plugin.dart';

/// The single place that answers "can Lumen open this file?".
///
/// The scanner, the thumbnailer, the viewer and the LAN server all ask here.
/// None of them tests a file extension itself, so adding a format is one entry
/// in [defaultPlugins] and nothing else.
class ImageFormatRegistry {
  ImageFormatRegistry(List<ImageFormatPlugin> plugins)
      : _plugins = List<ImageFormatPlugin>.unmodifiable(plugins) {
    _index = <String, ImageFormatPlugin>{};
    for (final plugin in _plugins) {
      for (final ext in plugin.extensions) {
        // First plugin to claim an extension wins, so the engine's native
        // formats always take the fast path even if a later plugin lists them.
        _index.putIfAbsent(ext.toLowerCase(), () => plugin);
      }
    }
  }

  static final ImageFormatRegistry instance =
      ImageFormatRegistry(defaultPlugins());

  final List<ImageFormatPlugin> _plugins;
  late final Map<String, ImageFormatPlugin> _index;

  List<ImageFormatPlugin> get plugins => _plugins;

  Set<String> get allExtensions => _index.keys.toSet();

  String? _extensionOf(String pathOrName) {
    final ext = p.extension(pathOrName);
    if (ext.length < 2) return null;
    return ext.substring(1).toLowerCase();
  }

  ImageFormatPlugin? pluginFor(String pathOrName) {
    final ext = _extensionOf(pathOrName);
    if (ext == null) return null;
    return _index[ext];
  }

  bool supports(String pathOrName) => pluginFor(pathOrName) != null;

  bool isSupportedExtension(String extension) {
    final cleaned = extension.startsWith('.')
        ? extension.substring(1).toLowerCase()
        : extension.toLowerCase();
    return _index.containsKey(cleaned);
  }

  /// Decode through whichever plugin claims the file. Returns null when the
  /// format is unknown, the plugin's library is missing, or the file is bad —
  /// never throws, because a single unreadable photo must not stop a scan.
  Future<ui.Image?> decode(File file, {int? targetWidth}) async {
    final plugin = pluginFor(file.path);
    if (plugin == null) return null;
    try {
      return await plugin.decode(file, targetWidth: targetWidth);
    } catch (_) {
      return null;
    }
  }

  /// True when the Flutter engine decodes this format in-process.
  bool isEngineNative(String pathOrName) => pluginFor(pathOrName)?.id == 'engine';

  /// Bytes a browser can actually render. Native formats are streamed as they
  /// are; anything else is transcoded once through its plugin.
  Future<List<int>?> browserBytes(File file) async {
    final plugin = pluginFor(file.path);
    if (plugin == null) return null;
    try {
      if (plugin.browserSafe) return await file.readAsBytes();
      if (plugin is ExternalDecoderPlugin) return await plugin.transcodeToPng(file);
    } catch (_) {}
    return null;
  }

  /// True when a browser can be handed the file as-is.
  bool isBrowserSafe(String pathOrName) {
    final plugin = pluginFor(pathOrName);
    if (plugin == null) return false;
    return plugin.browserSafe;
  }

  /// Status of every plugin, for the settings screen. Probes run in parallel;
  /// each one is cached inside the plugin, so this is cheap after the first call.
  Future<List<FormatStatus>> status() async {
    final results = await Future.wait(_plugins.map((plugin) async {
      FormatAvailability availability;
      try {
        availability = await plugin.probe();
      } catch (_) {
        availability = FormatAvailability.needsInstall;
      }
      return FormatStatus(plugin: plugin, availability: availability);
    }));
    return results;
  }

  /// The format plugins Lumen ships with.
  ///
  /// The engine handles the universal formats. Everything else is backed by an
  /// established open-source decoder and is only active when that decoder is
  /// installed — Lumen never bundles or downloads one.
  static List<ImageFormatPlugin> defaultPlugins() {
    return <ImageFormatPlugin>[
      const EngineImagePlugin(),
      _heifPlugin(),
      _tiffPlugin(),
      _rawPlugin(),
      _jxlPlugin(),
      _miscPlugin(),
    ];
  }

  // ImageMagick 7 is `magick`. ImageMagick 6 is `convert`, which on Windows is
  // also the name of the built-in FAT-to-NTFS tool — running that with a photo
  // path as an argument is not something to risk, so `convert` is never
  // offered on Windows.
  static List<DecoderCommand> _magickCandidates() {
    return <DecoderCommand>[
      DecoderCommand(
        executable: 'magick',
        label: 'ImageMagick 7',
        arguments: (input, output) => <String>[input, output],
      ),
      if (!Platform.isWindows)
        DecoderCommand(
          executable: 'convert',
          label: 'ImageMagick 6',
          arguments: (input, output) => <String>[input, output],
        ),
    ];
  }

  static ExternalDecoderPlugin _heifPlugin() => ExternalDecoderPlugin(
        id: 'heif',
        displayName: 'HEIC / HEIF / AVIF',
        extensions: const <String>['heic', 'heif', 'hif', 'avif'],
        poweredBy: 'libheif (LGPL-3.0), libavif (BSD-2-Clause)',
        requirement:
            'heif-convert on PATH — Debian/Ubuntu: sudo apt install libheif-examples; '
            'Windows: the libheif release bundle. ImageMagick also works.',
        commands: <DecoderCommand>[
          DecoderCommand(
            executable: 'heif-convert',
            label: 'heif-convert',
            arguments: (input, output) => <String>[input, output],
          ),
          ..._magickCandidates(),
        ],
      );

  static ExternalDecoderPlugin _tiffPlugin() => ExternalDecoderPlugin(
        id: 'tiff',
        displayName: 'TIFF',
        extensions: const <String>['tif', 'tiff'],
        poweredBy: 'libtiff (libtiff licence), via ImageMagick',
        requirement:
            'ImageMagick on PATH — Debian/Ubuntu: sudo apt install imagemagick; '
            'Windows: the ImageMagick installer.',
        commands: _magickCandidates(),
      );

  static ExternalDecoderPlugin _rawPlugin() => ExternalDecoderPlugin(
        id: 'raw',
        displayName: 'Camera RAW',
        extensions: const <String>[
          'cr2', 'cr3', 'nef', 'nrw', 'arw', 'srf', 'sr2', 'dng', 'raf',
          'rw2', 'orf', 'pef', 'srw', 'crw', 'mrw', 'x3f', '3fr', 'erf',
        ],
        poweredBy: 'LibRaw (LGPL-2.1 / CDDL-1.0) and darktable (GPL-3.0)',
        requirement:
            'darktable-cli or ImageMagick on PATH — darktable: sudo apt install darktable; '
            'Windows: the darktable installer. ImageMagick reads RAW through LibRaw.',
        commands: <DecoderCommand>[
          DecoderCommand(
            executable: 'darktable-cli',
            label: 'darktable-cli',
            arguments: (input, output) => <String>[input, output],
          ),
          ..._magickCandidates(),
        ],
      );

  static ExternalDecoderPlugin _jxlPlugin() => ExternalDecoderPlugin(
        id: 'jxl',
        displayName: 'JPEG XL',
        extensions: const <String>['jxl'],
        poweredBy: 'libjxl (BSD-3-Clause)',
        requirement:
            'djxl on PATH — Debian/Ubuntu: sudo apt install libjxl-tools; '
            'Windows: the libjxl release bundle. ImageMagick also works.',
        commands: <DecoderCommand>[
          DecoderCommand(
            executable: 'djxl',
            label: 'djxl',
            arguments: (input, output) => <String>[input, output],
          ),
          ..._magickCandidates(),
        ],
      );

  static ExternalDecoderPlugin _miscPlugin() => ExternalDecoderPlugin(
        id: 'misc',
        displayName: 'PSD / TGA / DDS / EXR / HDR',
        extensions: const <String>['psd', 'tga', 'dds', 'exr', 'hdr', 'pcx', 'ppm', 'pgm'],
        poweredBy: 'ImageMagick (ImageMagick licence)',
        requirement:
            'ImageMagick on PATH — Debian/Ubuntu: sudo apt install imagemagick; '
            'Windows: the ImageMagick installer.',
        commands: _magickCandidates(),
      );
}
