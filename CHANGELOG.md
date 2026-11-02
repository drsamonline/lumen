# Changelog

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
