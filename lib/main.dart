import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'core/app_paths.dart';
import 'core/db/database.dart';
import 'core/settings.dart';

/// Lumen entry point.
///
/// Startup is deliberately boring and fast: resolve paths, open the index,
/// then hand over to the widget tree. No network is ever touched.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop platforms have no bundled SQLite plugin, so we run sqflite on the
  // FFI implementation. Android keeps the default plugin factory.
  //
  // macOS and iOS are deliberately not targets: building either needs a macOS
  // machine, so they are out of scope for this project rather than untested.
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await AppPaths.init();
  await AppDatabase.instance.open();
  await Settings.init();

  runApp(const ProviderScope(child: LumenApp()));
}
