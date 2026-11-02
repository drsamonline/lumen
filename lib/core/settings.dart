import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Small preferences store. Library roots live in SQLite (they are data);
/// everything here is presentation and behaviour.
class Settings {
  Settings(this._prefs);

  final SharedPreferences _prefs;

  static const _kThumbSize = 'thumb_size';
  static const _kLanEnabled = 'lan_enabled';
  static const _kLanPort = 'lan_port';
  static const _kWatcherEnabled = 'watcher_enabled';
  static const _kGridView = 'grid_view';
  static const _kSort = 'sort';

  /// Loaded once during startup; every provider reads this instance.
  static late Settings instance;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    instance = Settings(prefs);
  }

  double get thumbSize => _prefs.getDouble(_kThumbSize) ?? 160;
  Future<void> setThumbSize(double v) => _prefs.setDouble(_kThumbSize, v);

  bool get lanEnabled => _prefs.getBool(_kLanEnabled) ?? false;
  Future<void> setLanEnabled(bool v) => _prefs.setBool(_kLanEnabled, v);

  int get lanPort => _prefs.getInt(_kLanPort) ?? 8421;
  Future<void> setLanPort(int v) => _prefs.setInt(_kLanPort, v);

  bool get watcherEnabled => _prefs.getBool(_kWatcherEnabled) ?? true;
  Future<void> setWatcherEnabled(bool v) => _prefs.setBool(_kWatcherEnabled, v);

  int get sortIndex => _prefs.getInt(_kSort) ?? 0;
  Future<void> setSortIndex(int v) => _prefs.setInt(_kSort, v);

  /// Reserved for future per-view state; kept typed so upgrades are painless.
  Map<String, dynamic> get gridView {
    final raw = _prefs.getString(_kGridView);
    if (raw == null) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return <String, dynamic>{};
  }
}
