/// Every extension Lumen indexes, as a pure-Dart constant.
///
/// Deliberately free of `dart:ui`. The indexer needs to know what a photo looks
/// like, and the command-line tool has to be able to ask that question without
/// dragging in the Flutter engine — `dart compile exe` cannot link `dart:ui`.
///
/// The plugins remain the source of truth for *decoding*; this is the source of
/// truth for *indexing*, and `test/extension_index_test.dart` fails if the two
/// ever disagree.
library;

const Set<String> kIndexedExtensions = <String>{
  // Flutter engine
  'jpg', 'jpeg', 'jfif', 'png', 'webp', 'gif', 'bmp', 'wbmp',
  // libheif / libavif
  'heic', 'heif', 'hif', 'avif',
  // libtiff
  'tif', 'tiff',
  // LibRaw
  'cr2', 'cr3', 'nef', 'nrw', 'arw', 'srf', 'sr2', 'dng', 'raf', 'rw2',
  'orf', 'pef', 'srw', 'crw', 'mrw', 'x3f', '3fr', 'erf',
  // libjxl
  'jxl',
  // ImageMagick
  'psd', 'tga', 'dds', 'hdr', 'exr', 'pcx', 'pgm', 'ppm',
};
