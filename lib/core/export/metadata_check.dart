import 'dart:io';
import 'dart:typed_data';

/// Reads a written image back and reports what identifying metadata is left in
/// it. "Nothing left" has to mean the bytes on disk, not the intent of the code
/// that wrote them — a decoder that quietly re-attaches an ICC profile or a
/// tIME chunk would otherwise go unnoticed.
class MetadataCheck {
  static const _pngBlocks = <String>{
    'eXIf', // EXIF
    'tEXt', // textual metadata, often the software name
    'iTXt', // international text
    'zTXt', // compressed text
    'tIME', // last-modified time
  };

  /// Returns the metadata blocks found. Empty means clean.
  static Future<List<String>> scan(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      final head = await handle.read(8);
      if (head.length >= 8 && head[0] == 0x89 && head[1] == 0x50) {
        return await _scanPng(handle);
      }
      if (head.length >= 2 && head[0] == 0xFF && head[1] == 0xD8) {
        await handle.setPosition(0);
        return await _scanJpeg(handle);
      }
      return const <String>['unknown container'];
    } catch (_) {
      return const <String>['unreadable'];
    } finally {
      await handle?.close();
    }
  }

  static Future<List<String>> _scanPng(RandomAccessFile handle) async {
    final found = <String>[];
    await handle.setPosition(8);
    final lengthBytes = Uint8List(4);
    final typeBytes = Uint8List(4);

    while (true) {
      if (await handle.readInto(lengthBytes) != 4) break;
      if (await handle.readInto(typeBytes) != 4) break;

      final length = (lengthBytes[0] << 24) |
          (lengthBytes[1] << 16) |
          (lengthBytes[2] << 8) |
          lengthBytes[3];
      final type = String.fromCharCodes(typeBytes);
      if (type == 'IEND') break;
      if (_pngBlocks.contains(type) && !found.contains(type)) found.add(type);

      // length + 4-byte CRC after the payload
      await handle.setPosition(await handle.position() + length + 4);
    }
    return found;
  }

  static Future<List<String>> _scanJpeg(RandomAccessFile handle) async {
    final found = <String>[];
    final length = await handle.length();
    var position = 2;

    while (position + 4 < length) {
      await handle.setPosition(position);
      final marker = await handle.read(2);
      if (marker.length < 2 || marker[0] != 0xFF) break;

      final kind = marker[1];
      if (kind == 0xD8 || kind == 0x01 || (kind >= 0xD0 && kind <= 0xD7)) {
        position += 2;
        continue;
      }
      if (kind == 0xDA) break; // start of scan: metadata is behind us

      final sizeBytes = await handle.read(2);
      if (sizeBytes.length < 2) break;
      final segmentLength = (sizeBytes[0] << 8) | sizeBytes[1];

      String? block;
      if (kind == 0xE1) block = 'APP1 (EXIF/XMP)';
      if (kind == 0xE2) block = 'APP2 (ICC)';
      if (kind == 0xED) block = 'APP13 (IPTC)';
      if (kind == 0xFE) block = 'COM';
      if (block != null && !found.contains(block)) found.add(block);

      position += 2 + segmentLength;
    }
    return found;
  }
}
