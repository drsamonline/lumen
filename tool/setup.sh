#!/usr/bin/env bash
# Generate the platform folders and fetch packages.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not on PATH. Install it from https://docs.flutter.dev/get-started/install" >&2
  exit 1
fi

echo "==> Generating platform folders"
flutter create --platforms=android,windows,linux,macos .

echo "==> Fetching packages"
flutter pub get

echo
echo "Done. Now run one of:"
echo "  flutter run -d windows"
echo "  flutter run -d linux"
echo "  flutter run -d macos"
echo "  flutter run -d <android-device-id>"
