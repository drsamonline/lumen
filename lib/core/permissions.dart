import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Photo-library access, where the platform needs asking.
///
/// Android 13+ replaced READ_EXTERNAL_STORAGE with READ_MEDIA_IMAGES, and either
/// way the grant is a runtime prompt — declaring it in the manifest only makes
/// the prompt possible. Windows and Linux have no equivalent: a desktop app reads
/// whatever the user's account can read.
class PhotoPermissions {
  static bool get _isAndroid => Platform.isAndroid;

  /// Asks for photo access if it has not already been granted.
  ///
  /// Returns true when the app can read the library. On desktop it is always
  /// true. A denial is not fatal — the folder picker still works — so callers
  /// treat false as "use the picker instead".
  static Future<bool> request() async {
    if (!_isAndroid) return true;
    try {
      final photos = await Permission.photos.status;
      if (photos.isGranted) return true;

      // Android 12 and below have no Permission.photos; storage covers it.
      final result = await <Permission>[Permission.photos, Permission.storage]
          .request();
      return result.values.any((status) => status.isGranted);
    } catch (_) {
      // A missing plugin or a platform that does not implement it must not stop
      // the user getting into the app.
      return false;
    }
  }

  /// True when the user has permanently refused, so the UI should point at
  /// system settings rather than asking again.
  static Future<bool> permanentlyDenied() async {
    if (!_isAndroid) return false;
    try {
      final photos = await Permission.photos.status;
      return photos.isPermanentlyDenied;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    try {
      await openAppSettings();
    } catch (_) {}
  }
}
