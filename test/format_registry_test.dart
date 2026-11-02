import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/formats/format_registry.dart';
import 'package:lumen/core/formats/image_format.dart';
import 'package:lumen/core/formats/plugins/engine_plugin.dart';

class FakePlugin implements ImageFormatPlugin {
  FakePlugin({
    required this.id,
    required this.extensions,
    this.availability = FormatAvailability.ready,
    this.browserSafe = false,
  });

  @override
  final String id;

  @override
  final List<String> extensions;

  @override
  final bool browserSafe;

  final FormatAvailability availability;

  int probes = 0;

  @override
  String get displayName => 'Fake $id';

  @override
  String get poweredBy => 'nothing';

  @override
  String? get requirement => 'install something';

  @override
  Future<FormatAvailability> probe() async {
    probes++;
    return availability;
  }

  @override
  Future<ui.Image?> decode(File file, {int? targetWidth}) async => null;
}

void main() {
  group('extension routing', () {
    late ImageFormatRegistry registry;

    setUp(() {
      registry = ImageFormatRegistry(<ImageFormatPlugin>[
        const EngineImagePlugin(),
        FakePlugin(id: 'heif', extensions: const <String>['heic', 'heif', 'avif']),
        FakePlugin(id: 'raw', extensions: const <String>['cr2', 'nef', 'dng']),
      ]);
    });

    test('routes a native format to the engine', () {
      expect(registry.pluginFor('/photos/holiday.jpg')?.id, 'engine');
      expect(registry.pluginFor('screenshot.PNG')?.id, 'engine');
      expect(registry.isEngineNative('a.webp'), isTrue);
    });

    test('routes an exotic format to its plugin', () {
      expect(registry.pluginFor('/photos/IMG_0001.HEIC')?.id, 'heif');
      expect(registry.pluginFor('shot.avif')?.id, 'heif');
      expect(registry.pluginFor('DSC_0042.NEF')?.id, 'raw');
      expect(registry.isEngineNative('shot.avif'), isFalse);
    });

    test('returns null for formats nobody claims', () {
      expect(registry.pluginFor('document.pdf'), isNull);
      expect(registry.pluginFor('notes.txt'), isNull);
      expect(registry.pluginFor('noextension'), isNull);
      expect(registry.supports('movie.mp4'), isFalse);
    });

    test('is case-insensitive and dot-tolerant', () {
      expect(registry.isSupportedExtension('jpg'), isTrue);
      expect(registry.isSupportedExtension('.JPG'), isTrue);
      expect(registry.isSupportedExtension('.HeIc'), isTrue);
      expect(registry.isSupportedExtension('mp4'), isFalse);
    });

    test('the first plugin to claim an extension wins', () {
      // A later plugin re-listing jpg must not displace the engine's fast path.
      final shadowed = ImageFormatRegistry(<ImageFormatPlugin>[
        const EngineImagePlugin(),
        FakePlugin(id: 'shadow', extensions: const <String>['jpg', 'tga']),
      ]);
      expect(shadowed.pluginFor('a.jpg')?.id, 'engine');
      expect(shadowed.pluginFor('a.tga')?.id, 'shadow');
    });

    test('allExtensions is the union', () {
      final all = registry.allExtensions;
      expect(all, containsAll(<String>['jpg', 'png', 'heic', 'cr2', 'dng']));
    });

    test('browser safety follows the plugin', () {
      expect(registry.isBrowserSafe('a.jpg'), isTrue);
      expect(registry.isBrowserSafe('a.heic'), isFalse);
      expect(registry.isBrowserSafe('a.unknown'), isFalse);
    });
  });

  group('shipped plugins', () {
    test('cover the formats the roadmap promised', () {
      final registry = ImageFormatRegistry(ImageFormatRegistry.defaultPlugins());
      for (final ext in <String>[
        'jpg', 'png', 'webp', 'gif', 'bmp', // engine
        'heic', 'heif', 'avif', // libheif
        'tif', 'tiff', // libtiff
        'cr2', 'nef', 'arw', 'dng', 'raf', 'orf', // LibRaw
        'jxl', // libjxl
        'psd', 'tga', // ImageMagick
      ]) {
        expect(registry.isSupportedExtension(ext), isTrue, reason: ext);
      }
    });

    test('every plugin declares what backs it', () {
      for (final plugin in ImageFormatRegistry.defaultPlugins()) {
        expect(plugin.poweredBy, isNotEmpty, reason: plugin.id);
        expect(plugin.extensions, isNotEmpty, reason: plugin.id);
        // Only the built-in engine has nothing to install.
        if (plugin.id == 'engine') {
          expect(plugin.requirement, isNull);
        } else {
          expect(plugin.requirement, isNotNull, reason: plugin.id);
        }
      }
    });

    test('status reports one row per plugin', () async {
      final registry = ImageFormatRegistry(<ImageFormatPlugin>[
        const EngineImagePlugin(),
        FakePlugin(id: 'a', extensions: const <String>['aaa']),
        FakePlugin(
          id: 'b',
          extensions: const <String>['bbb'],
          availability: FormatAvailability.needsInstall,
        ),
      ]);
      final statuses = await registry.status();
      expect(statuses.length, 3);
      expect(statuses.first.availability, FormatAvailability.builtIn);
      expect(
        statuses.where((s) => s.availability == FormatAvailability.needsInstall).length,
        1,
      );
    });
  });
}
