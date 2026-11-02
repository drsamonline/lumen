import 'dart:io';
import 'dart:typed_data';

/// A store-only ZIP writer.
///
/// Photos are already compressed — JPEG and PNG gain nothing from a second
/// DEFLATE pass, so storing them costs no size and makes writing an album
/// roughly as fast as copying the files. Streaming straight to disk means a
/// 4 GB album does not need 4 GB of RAM.
class ZipSource {
  const ZipSource.bytes(this.name, this.bytes) : file = null;
  const ZipSource.file(this.name, File this.file) : bytes = null;

  final String name;
  final List<int>? bytes;
  final File? file;

  Future<int> get length async =>
      bytes?.length ?? await file!.length();

  Future<List<int>> read() async => bytes ?? await file!.readAsBytes();
}

class ZipArchiveWriter {
  ZipArchiveWriter._();

  /// Write [sources] into [target]. Returns the number of bytes written.
  static Future<int> write(File target, List<ZipSource> sources) async {
    final sink = target.openWrite();
    var offset = 0;
    final central = <_CentralEntry>[];

    Future<void> emit(List<int> data) async {
      sink.add(data);
      offset += data.length;
    }

    try {
      for (final source in sources) {
        final data = await source.read();
        final nameBytes = _utf8(source.name);
        final crc = Crc32.compute(data);
        final now = DateTime.now();
        final dosTime = _dosTime(now);
        final dosDate = _dosDate(now);
        final localOffset = offset;

        final header = _Out()
          ..u32(0x04034b50) // local file header
          ..u16(20) // version needed
          ..u16(0x0800) // UTF-8 filename flag
          ..u16(0) // method: store
          ..u16(dosTime)
          ..u16(dosDate)
          ..u32(crc)
          ..u32(data.length)
          ..u32(data.length)
          ..u16(nameBytes.length)
          ..u16(0);
        await emit(header.take());
        await emit(nameBytes);
        await emit(data);

        central.add(_CentralEntry(
          nameBytes: nameBytes,
          crc: crc,
          size: data.length,
          offset: localOffset,
          dosTime: dosTime,
          dosDate: dosDate,
        ));
      }

      final centralStart = offset;
      for (final entry in central) {
        final out = _Out()
          ..u32(0x02014b50) // central directory header
          ..u16(20)
          ..u16(20)
          ..u16(0x0800)
          ..u16(0)
          ..u16(entry.dosTime)
          ..u16(entry.dosDate)
          ..u32(entry.crc)
          ..u32(entry.size)
          ..u32(entry.size)
          ..u16(entry.nameBytes.length)
          ..u16(0) // extra
          ..u16(0) // comment
          ..u16(0) // disk
          ..u16(0) // internal attrs
          ..u32(0) // external attrs
          ..u32(entry.offset);
        await emit(out.take());
        await emit(entry.nameBytes);
      }
      final centralSize = offset - centralStart;

      final end = _Out()
        ..u32(0x06054b50) // end of central directory
        ..u16(0)
        ..u16(0)
        ..u16(central.length)
        ..u16(central.length)
        ..u32(centralSize)
        ..u32(centralStart)
        ..u16(0);
      await emit(end.take());

      await sink.flush();
      return offset;
    } finally {
      await sink.close();
    }
  }

  static List<int> _utf8(String s) {
    final bytes = <int>[];
    for (final rune in s.runes) {
      if (rune < 0x80) {
        bytes.add(rune);
      } else if (rune < 0x800) {
        bytes..add(0xC0 | (rune >> 6))..add(0x80 | (rune & 0x3F));
      } else if (rune < 0x10000) {
        bytes
          ..add(0xE0 | (rune >> 12))
          ..add(0x80 | ((rune >> 6) & 0x3F))
          ..add(0x80 | (rune & 0x3F));
      } else {
        bytes
          ..add(0xF0 | (rune >> 18))
          ..add(0x80 | ((rune >> 12) & 0x3F))
          ..add(0x80 | ((rune >> 6) & 0x3F))
          ..add(0x80 | (rune & 0x3F));
      }
    }
    return bytes;
  }

  static int _dosTime(DateTime t) => (t.hour << 11) | (t.minute << 5) | (t.second ~/ 2);

  static int _dosDate(DateTime t) {
    final year = t.year.clamp(1980, 2107);
    return ((year - 1980) << 9) | (t.month << 5) | t.day;
  }
}

class _CentralEntry {
  _CentralEntry({
    required this.nameBytes,
    required this.crc,
    required this.size,
    required this.offset,
    required this.dosTime,
    required this.dosDate,
  });

  final List<int> nameBytes;
  final int crc;
  final int size;
  final int offset;
  final int dosTime;
  final int dosDate;
}

/// CRC-32 (IEEE 802.3), the checksum ZIP requires.
class Crc32 {
  static final List<int> _table = _buildTable();

  static List<int> _buildTable() {
    final table = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      }
      table[i] = c;
    }
    return table;
  }

  static int compute(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc = _table[(crc ^ byte) & 0xFF] ^ (crc >>> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

class _Out {
  final BytesBuilder _builder = BytesBuilder(copy: true);

  void u16(int value) {
    _builder.addByte(value & 0xFF);
    _builder.addByte((value >> 8) & 0xFF);
  }

  void u32(int value) {
    _builder.addByte(value & 0xFF);
    _builder.addByte((value >> 8) & 0xFF);
    _builder.addByte((value >> 16) & 0xFF);
    _builder.addByte((value >> 24) & 0xFF);
  }

  Uint8List take() => _builder.takeBytes();
}
