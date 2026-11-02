# Generate the platform folders and fetch packages (Windows).
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error 'Flutter is not on PATH. Install it from https://docs.flutter.dev/get-started/install'
}

Write-Host '==> Generating platform folders'
flutter create --platforms=android,windows,linux,macos .

Write-Host '==> Fetching packages'
flutter pub get

Write-Host ''
Write-Host 'Done. Now run: flutter run -d windows'
