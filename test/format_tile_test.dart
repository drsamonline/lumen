import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/formats/image_format.dart';
import 'package:lumen/ui/widgets/format_tile.dart';

/// A plugin that claims as many extensions as RAW does.
class _LongPlugin implements ImageFormatPlugin {
  @override
  String get id => 'raw';
  @override
  String get displayName => 'Camera RAW';
  @override
  List<String> get extensions => const <String>[
        'cr2', 'cr3', 'nef', 'nrw', 'arw', 'srf', 'sr2', 'dng', 'raf',
        'rw2', 'orf', 'pef', 'srw', 'crw', 'mrw', 'x3f', '3fr', 'erf',
      ];
  @override
  String get poweredBy => 'LibRaw (LGPL-2.1 / CDDL-1.0) and darktable (GPL-3.0)';
  @override
  String? get requirement =>
      'darktable-cli or ImageMagick on PATH — darktable: sudo apt install '
      'darktable. ImageMagick reads RAW through LibRaw.';
  @override
  bool get browserSafe => false;
  @override
  Future<FormatAvailability> probe() async => FormatAvailability.needsInstall;
  @override
  Future<ui.Image?> decode(File file, {int? targetWidth}) async => null;
}

void main() {
  // This is the regression guard for the bug the phone screenshots showed: the
  // settings row overflowed so hard that the plugin name was squeezed to one
  // character per line. A RenderFlex overflow throws in a widget test, so
  // pumping the row at phone width fails the build if it comes back.
  testWidgets('a long extension list does not overflow at phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              FormatTile(
                status: FormatStatus(
                  plugin: _LongPlugin(),
                  availability: FormatAvailability.needsInstall,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Camera RAW'), findsOneWidget);
  });

  testWidgets('a narrow window still lays out', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormatTile(
            status: FormatStatus(
              plugin: _LongPlugin(),
              availability: FormatAvailability.needsInstall,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  test('the extension list is capped', () {
    final status = FormatStatus(
      plugin: _LongPlugin(),
      availability: FormatAvailability.needsInstall,
    );
    expect(status.extensionsLabel, contains('+12 more'));
    expect(status.extensionsLabel.split(',').length, lessThan(9));
  });
}
