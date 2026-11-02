import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import '../image_format.dart';

/// A decoder command, tried in order until one is present.
class DecoderCommand {
  const DecoderCommand({
    required this.executable,
    required this.arguments,
    this.label,
  });

  final String executable;

  /// Builds the argument list for `input -> output`. The output is always a
  /// file with an extension the Flutter engine can read, so the result can be
  /// decoded in-process.
  final List<String> Function(String input, String output) arguments;

  final String? label;

  String get displayName => label ?? executable;
}

/// A format plugin backed by an open-source library installed on the machine.
///
/// The binding is each project's own command-line tool rather than an FFI
/// shim: it needs no compilation, no per-platform build, and it cannot crash
/// the app if a library is subtly mismatched. The trade is a process spawn per
/// file — acceptable because this path only runs for formats the engine cannot
/// read, and thumbnails are generated once and cached.
///
/// An FFI plugin implements the same [ImageFormatPlugin] interface, so wiring
/// one in later needs no changes anywhere else.
class ExternalDecoderPlugin implements ImageFormatPlugin {
  ExternalDecoderPlugin({
    required this.id,
    required this.displayName,
    required this.extensions,
    required this.poweredBy,
    required this.requirement,
    required this.commands,
  });

  @override
  final String id;

  @override
  final String displayName;

  @override
  final List<String> extensions;

  @override
  final String poweredBy;

  @override
  final String requirement;

  final List<DecoderCommand> commands;

  /// These produce a PNG we then decode, so the *output* is browser-safe even
  /// though the source was not.
  @override
  bool get browserSafe => false;

  DecoderCommand? _resolved;
  bool _probed = false;

  /// The command that answered, once known — shown in settings so the user can
  /// see which tool is actually doing the work.
  DecoderCommand? get resolvedCommand => _resolved;

  @override
  Future<FormatAvailability> probe() async {
    if (_probed) {
      return _resolved == null
          ? FormatAvailability.needsInstall
          : FormatAvailability.ready;
    }
    _probed = true;

    // A spawned shell is not available on Android; skip the search there
    // rather than paying a ProcessException per candidate.
    if (Platform.isAndroid) {
      _resolved = null;
      return FormatAvailability.needsInstall;
    }

    for (final command in commands) {
      if (await _canRun(command.executable)) {
        _resolved = command;
        return FormatAvailability.ready;
      }
    }
    _resolved = null;
    return FormatAvailability.needsInstall;
  }

  static Future<bool> _canRun(String executable) async {
    try {
      // Do not check the exit code: most of these print usage and exit non-zero
      // when given --version. Starting at all is the only thing we need.
      await Process.run(executable, const <String>['--version']);
      return true;
    } on ProcessException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ui.Image?> decode(File file, {int? targetWidth}) async {
    final availability = await probe();
    if (availability != FormatAvailability.ready) return null;
    final command = _resolved;
    if (command == null) return null;

    Directory? temp;
    try {
      temp = await Directory.systemTemp.createTemp('lumen_fmt');
      final output = p.join(temp.path, 'decoded.png');
      final result = await Process.run(
        command.executable,
        command.arguments(file.path, output),
      );
      if (result.exitCode != 0) return null;

      final decoded = File(output);
      if (!await decoded.exists()) return null;

      final bytes = await decoded.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    } finally {
      if (temp != null) {
        try {
          await temp.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// Raw bytes of a decodable stand-in, used by the LAN server for formats a
  /// browser cannot render.
  Future<Uint8List?> transcodeToPng(File file) async {
    final availability = await probe();
    if (availability != FormatAvailability.ready) return null;
    final command = _resolved;
    if (command == null) return null;

    Directory? temp;
    try {
      temp = await Directory.systemTemp.createTemp('lumen_fmt');
      final output = p.join(temp.path, 'served.png');
      final result = await Process.run(
        command.executable,
        command.arguments(file.path, output),
      );
      if (result.exitCode != 0) return null;
      final decoded = File(output);
      if (!await decoded.exists()) return null;
      return await decoded.readAsBytes();
    } catch (_) {
      return null;
    } finally {
      if (temp != null) {
        try {
          await temp.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}
