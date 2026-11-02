/// The version the app reports.
///
/// Injected at build time so it cannot drift from the tag:
///
///     flutter build apk --release --dart-define=APP_VERSION=1.6.2
///
/// The settings screen used to print a hardcoded "1.0.0" while the release was
/// 1.6.1, which is worse than printing nothing — it tells the person reporting a
/// bug the wrong build.
const String kAppVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
