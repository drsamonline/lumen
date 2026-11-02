import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/formats/extension_index.dart';
import 'package:lumen/core/formats/format_registry.dart';

void main() {
  test('the indexer accepts exactly what the plugins can decode', () {
    final decodable = <String>{
      for (final plugin in ImageFormatRegistry.instance.plugins)
        ...plugin.extensions.map((e) => e.toLowerCase()),
    };

    expect(
      kIndexedExtensions.difference(decodable),
      isEmpty,
      reason: 'the indexer would accept files nothing can open',
    );
    expect(
      decodable.difference(kIndexedExtensions),
      isEmpty,
      reason: 'a plugin can decode a format the indexer would never find',
    );
  });

  test('the predicate tolerates dots and case', () {
    expect(PhotoDaoExt.contains('jpg'), isTrue);
  });
}

/// Tiny shim so the test reads as a sentence without importing the DAO.
abstract final class PhotoDaoExt {
  static bool contains(String ext) =>
      kIndexedExtensions.contains(ext.replaceFirst('.', '').toLowerCase());
}
