# Changelog

## 1.6.2 - Android could not open its database

The error screen added in 1.6.1 did its job on the first run: it named the
exception instead of showing a blank window.

- **Cause.** `PRAGMA journal_mode = WAL` returns a row. sqflite's Android plugin
  rejects `execute()` for any statement that returns rows - "Queries can be
  performed using SQLiteDatabase query or rawQuery methods only" - so
  `onConfigure` threw, the database never opened, and startup aborted before the
  first frame. The FFI factory used on desktop is permissive about this, which is
  why every desktop build and every test passed.
- **Fix.** Every pragma now goes through `rawQuery` inside a guarded `_pragma`
  helper that swallows failures. A pragma is an optimisation; a photo library
  that will not start because it could not set a cache size is not a photo
  library.
- **Regression guard.** `test/db_pragma_test.dart` scans `lib/` for
  `execute('PRAGMA` and fails the build, so this cannot come back.

## 1.6.1 - Android: report startup failures, and ask for photos

- **Startup is wrapped.** Everything in `main()` runs before the first frame, so
  an exception there painted nothing at all. A failure now shows a readable
  screen with the error, the stack and a Copy button.
- **The Android manifest had no permissions.** The repo does not commit
  `android/`, so every build started from the bare manifest `flutter create`
  writes. `tools/android_permissions.py` adds the six the app needs, plus
  cleartext for the LAN gallery; it is idempotent and wired into both workflows.
- **`permission_handler`** asks for photo access at the right moment, with a
  Settings shortcut when permanently denied.
- **Onboarding dead end fixed** on Android: it tested `existsSync()` before
  asking, and under scoped storage those folders are invisible until the grant
  lands, so "Use camera roll" added nothing and Start stayed disabled.

## 1.6.0 - real installable builds

- `.github/workflows/release.yml` builds Windows x64, Linux x64 and an Android
  APK on a `v*` tag and attaches all three to a GitHub Release.
- `tools/demo_photos.py`: `--from <folder>` replaces the demo gallery's frames
  with real photographs in one command.

## 1.5.1 - audit of the tone-curve work

Found by reading the new code end to end, before CI could report on it.

- **A linear curve made a recipe non-identity.** `isIdentity` tested for the
  *presence* of a curve rather than its effect, so saving a straight diagonal
  stored a recipe that did nothing — and the test that asserted otherwise would
  have failed. It now evaluates the curve.
- **The curve editor only repainted by accident.** `shouldRepaint` compared the
  point list by identity, but the list is mutated in place; it repainted only
  because a fresh LUT was built each frame. Now explicit.
- **The slideshow ignored curves.** It decoded only for non-native formats, so
  a curved photo played unedited. It now uses the same rule as the viewer.
- **Hand-rolled `sqrt` replaced** with `dart:math` in the Fritsch-Carlson
  limiter. There was no reason for it.
- **Unused imports and an unused field** removed from the curve editor and the
  edit panel; `applyCurve` now returns non-null so callers stop reasoning about
  a half-applied edit.

Also documented the LAN gallery limitation: it streams originals, so edits are
visible in the thumbnail and the app but not at full size in a browser.

## 1.5.0 - tone curves, and macOS removed for good

**Tone curves**

- `ToneCurve` with monotone cubic (Fritsch-Carlson) interpolation to a 256-entry
  LUT. A plain spline overshoots between control points, which on a tone curve
  shows as a bright ring around a dark edge.
- Applied on the CPU, not in a fragment shader, so the grid thumbnail, the
  viewer and the exported PNG use the same numbers and no driver can compile a
  shader and then draw nothing.
- Curve editor: draggable points, tap to add, long-press to remove, six presets
  (Linear, Medium contrast, Strong contrast, Lift shadows, Matte, Bright).
- Live preview debounced at 240 ms, so dragging stays smooth.
- Stored as control points in the recipe, not as a 256-byte table.

**Fixed while adding it**

- **The grid thumbnail ignored every edit.** Saving a recipe updated the
  database and the viewer, and left the tile showing the original photo.
  `ARCHITECTURE.md` claimed the opposite. Saving now regenerates the thumbnail
  through the same `Exporter.render` path the export uses.
- **`Exporter.render` is now shared** by export and thumbnail, so the two cannot
  drift apart on order of operations.

**macOS and iOS removed**

- Neither is a target, permanently: building either needs a macOS machine, and
  this project will not carry that cost.
- Purged from the pubspec description, README, setup scripts, roadmap, decoder
  install hints and the repo description. `main.dart` no longer tests
  `Platform.isMacOS`.
- `ROADMAP.md` records it under "deliberately not doing" so it does not get
  proposed again.

## 1.4.6 - Windows build: runner image, not our code

Run 8 was the first three-platform run. Linux and Android both compiled; the
Windows job failed before touching any of our Dart.

- **Cause.** CMake reported `Generator Visual Studio 16 2019 could not find any
  instance of Visual Studio`. Flutter's Windows build needs Visual Studio with
  the "Desktop development with C++" workload, and when it cannot find one it
  falls back to a hardcoded VS 2019 generator string rather than saying so.
- **Fix.** The job is pinned to `windows-2022` instead of `windows-latest`, and
  a `flutter doctor -v` step now runs before the build so the Visual Studio
  version and workload status appear in the log. Without it the only signal was
  a CMake error naming a generator nobody asked for.
- **Not fixed by changing our code**, because there was nothing in our code to
  change. Worth recording anyway: the first instinct with a red Windows build
  is to look for a Windows-specific bug in the app, and there wasn't one.

## 1.4.5 - three platforms verified

The first green run proved Linux compiles with every native plugin linked. The
other two thirds of the cross-platform claim were still untested, so the
workflow now builds all three:

- **Linux desktop** - GTK toolchain, `flutter build linux --debug`.
- **Windows desktop** - `windows-latest`, `flutter build windows --debug`. This
  is the job that catches `sqflite_common_ffi` or `file_picker` disagreeing with
  a Windows API.
- **Android APK** - JDK 17, `flutter build apk --debug`.

macOS is deliberately not built: it needs a macOS runner, which is billed at a
higher rate. It remains the one platform with no compile evidence.

Run 7 (Linux) was the first fully green run: analysis clean, 97 tests passing,
desktop compile succeeded.

## 1.4.4 - first test run: 95 passing, 2 failing

Static analysis is green. The suite ran under a real Dart VM for the first
time: 95 passed, 2 failed. Both fixed.

- **Real bug: saturation -1 did not fully desaturate.** `colorMatrix()`
  clamped the adjustment to -0.95 before mapping it, so pulling Saturation all
  the way down left 5% of the original colour in the image. The same clamp was
  on contrast. Both now use the full -1..1 range, where the endpoints are
  meaningful: saturation -1 is the standard luminance matrix, contrast -1 is a
  zero-gain matrix.
- **Wrong test, not wrong code:** `totalBytes` selected `page().take(2)` and
  assumed insertion order. `page()` orders by `taken_at_ms DESC, id DESC`, so
  the first two rows were the last two inserted. The test now picks by file
  name, and a second case covers ids that are not in the library.

Everything else passed on the first run, including the ones that were guesses:
the ZIP round-trip through the system `unzip`, the scanner's skip-directory
rule, and all seven search-fallback cases.

## 1.4.3 - first CI run, first real findings

The first `flutter analyze` run reported 18 issues. All fixed; the build is now
clean at info level too, not just warning level.

- **Unused `dart:io` import** in `people_screen.dart` - the only *fatal* one.
  Warnings are fatal in CI by design, so this alone turned the build red.
- **Two `use_build_context_synchronously` findings** - a `BuildContext` was used
  after an `await` in the settings LAN toggle and the editor's Apply button. Both
  now capture `ScaffoldMessenger` / `Navigator` *before* the first await, which
  is the correct fix rather than suppressing the lint.
- **`prefer_const_declarations`** and **`prefer_const_constructors`** - two
  missed `const`s.
- **`prefer_interpolation_to_compose_strings`** in a test.
- **`prefer_single_quotes` disabled**, with the reason recorded in
  `analysis_options.yaml`: this codebase writes multi-line SQL in double-quoted
  triple blocks, and the lint would force single-quoted triple blocks around
  every `CREATE TABLE`, which breaks as soon as a query contains an apostrophe.
- **Dependabot now ignores major versions.** It opened four PRs on the first
  run, including `flutter_riverpod` 2 to 3, which is a breaking migration and
  must not land unreviewed.

## 1.4.2 — continuous integration

- **`.github/workflows/test.yml`.** `flutter analyze` and `flutter test` on every
  push and pull request, plus a Linux desktop debug build that proves the native
  plugins link. Flutter is pinned to 3.27.4 in one place.
- **`flutter analyze` is deliberately fatal on warnings**, so an unused import
  or a dead field turns the badge red instead of accumulating quietly.
- **No `flutter create` in the test job** — it would drop a generated
  `test/widget_test.dart` into the tree and fail the suite for no reason.
- **`.github/dependabot.yml`** for actions and pub packages, weekly.

## 1.4.1 — audit pass

No new features. Nine defects found by reading the tree end to end, all fixed,
each with a regression test where one was possible.

- **Bulk actions edited the wrong controller.** `BatchActionBar` read
  `libraryControllerProvider` instead of the controller that owned the grid, so
  rating or favouriting inside an album changed the database and nothing on
  screen. It now takes the controller as a parameter.
- **Fuzzy search ignored every non-text filter.** The candidate pool was "the
  newest 8000 photos" with no album, person, rating, favourite, date or place
  constraint, so a typo search inside an album could return photos from outside
  it. The pool is now built from the filter.
- **Transposed typos never matched.** "reciept" for "receipt" is two
  substitutions under plain Levenshtein, so the canonical English typo fell
  through. `Fuzzy` now accepts one adjacent transposition (Damerau).
- **The scanner indexed skipped directories.** `Directory.list` cannot prune a
  subtree, so the skip list was decorative — every image inside `node_modules`,
  `.cache` and `.git` was indexed. Path segments are now checked per entry.
- **Disposing a decoded image could crash.** The viewer and slideshow disposed a
  `ui.Image` while a mounted `RawImage` still referenced it, which throws
  "Cannot draw a disposed image" rather than showing the next photo. Disposal is
  now deferred one frame (`deferImageDisposal`).
- **A swiped-to exotic photo stayed blank** in the slideshow until the
  auto-advance timer happened to rebuild. `_load` now notifies.
- **Duplicate groups reported the wrong photo's dimensions** in the summary
  line — it read `photos.first` while labelling it "best".
- **The place filter had no chip**, so once applied it could not be cleared.
- **Dead code removed:** the unused `distance` map in the duplicate finder, an
  unused `AppDatabase` handle, `emptyBytes`, and two unused imports.
  `CropMath.fitAspect` was reachable only from tests; it now backs the preset
  behaviour when nothing has been cropped yet.

New tests: `scanner_test.dart` (skip directories, incremental rescan, vanished
files), `search_fallback_test.dart` (all three search stages, and that each
respects the rest of the filter).

## 1.4.0

- **Year scrubber.** A vertical year rail down the right edge of the grid. Drag
  or tap to jump to a year; the active year highlights. Offsets are computed
  arithmetically from the grid delegate's own column formula rather than
  measured, so it works on content that was never laid out.
- **Slideshow mode.** Full screen, auto-advance at 3/5/8/15 seconds, arrow keys
  to step, space to pause, Escape to exit, tap left/right thirds to move. Loads
  the current photo and the next two so a transition never shows a blank frame.
  Reachable from the library overflow menu and from the viewer.
- **Places.** Photos grouped by rounded coordinate, largest first, with a
  representative thumbnail. Tapping one filters the grid by a bounding box.
  No map tiles and no reverse geocoding — both would need a network.
- **`PhotoFilter` gains a geographic box** (`nearLat`, `nearLon`, `radiusDeg`),
  so a place is just another filter and reuses the existing scoped controller.
- **Library overflow menu** replaces the growing row of app-bar icons.
- `searchLibraryProvider` renamed to `filteredLibraryProvider` — it serves any
  filter, not only a search.

## 1.3.0

- **Multi-select.** Long-press to start, tap to toggle. Selection state is local
  to the grid so the library and album views cannot leak into each other.
- **Bulk action bar.** 0-5 stars, favourite / unfavourite, add to album, export
  as ZIP, clear — each in a single transaction.
- **Interactive crop.** Corner handles, rule-of-thirds guides, aspect presets
  (Free, 1:1, 4:3, 3:4, 3:2, 16:9) and reset. Replaces the placeholder
  square-crop button.
- **`CropMath`** — pure geometry, unit-tested: no inversion, aspect preserved at
  the frame edge, minimum size enforced.
- **Shared `AlbumZip`** so album export and selection export behave identically.
- `PhotoDao.totalBytes` for reporting selection size.

## 1.2.0

- **Pluggable image formats.** `ImageFormatPlugin` + `ImageFormatRegistry`;
  the scanner, thumbnailer, viewer and LAN server all route through the registry
  instead of testing file extensions. Adding a format is one plugin entry.
- **Open-source decoder plugins** for HEIC/HEIF/AVIF (libheif, libavif), TIFF
  (libtiff), camera RAW (LibRaw / darktable), JPEG XL (libjxl) and
  PSD/TGA/DDS/EXR/HDR (ImageMagick). Each is active only when its tool is on
  `PATH`; nothing is bundled or downloaded.
- **Settings reports every plugin** with its readiness, its backing library and
  the exact command to install.
- **LAN gallery transcodes** formats a browser cannot render, via a new `/view/`
  route, so HEIC and RAW still open on a phone or TV.
- The viewer decodes non-native formats through the registry and feeds the same
  non-destructive edit stack.
- Guard: ImageMagick's legacy `convert` binary is never invoked on Windows.

## 1.1.0

Feature work, mostly ported from the rest of the fleet (see `CREDITS.md`).

- **Duplicate detection.** 64-bit perceptual hash from the existing thumbnails,
  banded candidate lookup, union-find grouping, keep-best ranking. Read-only —
  Lumen never deletes a photo.
- **Album export as ZIP.** Store-only and streamed to disk.
- **Verified metadata stripping.** Exported files are read back and scanned for
  EXIF/XMP/IPTC/PNG text blocks; the UI reports what was measured, not what was
  intended.
- **Three-stage search.** Exact → substring → one-edit typo tolerance, with the
  result bar naming the stage that answered.
- Database schema v2: adds `photos.dhash` plus an index, with an `onUpgrade`
  migration so an existing library is not lost.

## 1.0.0

First working build: indexing with incremental rescans, timeline grid, EXIF and
GPS, ratings and favourites, non-destructive edits, manual face tagging, virtual
albums, FTS5 search, LAN gallery, and the offline guard test.
