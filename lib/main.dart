import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'core/app_paths.dart';
import 'core/db/database.dart';
import 'core/settings.dart';
import 'ui/startup_failure.dart';

/// Lumen entry point.
///
/// Startup is deliberately boring and fast: resolve paths, open the index, then
/// hand over to the widget tree. No network is ever touched.
///
/// Everything here runs *before* the first frame, which is why it is wrapped: an
/// exception in this function produces a blank window with no red screen and no
/// message, and the user has nothing to report. The catch below turns that into
/// a screen they can read and copy.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A widget that throws during build should say so, not paint a grey box.
  ErrorWidget.builder = (details) => StartupFailureApp(
        error: details.exception,
        stack: details.stack,
      );

  try {
    await _boot();
  } catch (error, stack) {
    debugPrint('Lumen failed to start: $error\n$stack');
    runApp(StartupFailureApp(error: error, stack: stack));
  }
}

Future<void> _boot() async {
  // Desktop platforms have no bundled SQLite plugin, so we run sqflite on the
  // FFI implementation. Android keeps the default plugin factory.
  //
  // Apple platforms are deliberately not targets: building either needs a Mac,
  // so they are out of scope for this project rather than untested.
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await AppPaths.init();
  await AppDatabase.instance.open();
  await Settings.init();

  runApp(const ProviderScope(child: LumenApp()));
}
