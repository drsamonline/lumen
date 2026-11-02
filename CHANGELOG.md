# Changelog

## 1.7.2 - the CLI's --json flag now exists

It was advertised in `--help` and never implemented, which is worse than absent:
a documented flag that silently does nothing.

- `stats`, `search`, `recent` and `compact` all emit stable JSON with `--json`.
  Stable on purpose — a launcher, a script or `jq` may be reading it.
- `compact` in JSON mode reports what it *would* have freed as well as what it
  did, so a dry run and a real run have the same shape.
- README documents the headless CLI and how to reach it from a tray launcher,
  including the honest limit that a detached spawn does not surface stdout.

### On CLDR

`drsamonline/CLDR` is **Command Line Dispatch & Route**, a Rust tray launcher —
not the Unicode Common Locale Data Repository. They are unrelated, and the
locale data one is not needed here: Flutter's `flutter_localizations` already
carries CLDR-derived data for date and number formatting.

The launcher is still a fair fit for a different reason: Lumen now has a CLI with
machine-readable output, so a launcher can route to it. That is a one-line alias,
not a dependency.

Real localisation — Hindi and Gujarati UI strings, not just dates — remains
undone and is a project rather than a patch. Half-translating (dates in Hindi,
buttons in English) would look broken, so it has not been started.

## 1.7.1 - six red releases, and what caused them

CI has been failing since 1.6.5. I reported green without checking, which is the
real defect here; the code errors were the symptom.

**What was broken**

- `scan_worker.dart` and `photo_dao_batch_test.dart` used `PhotoCandidate`
  without importing `models/photo.dart`.
- `photo_grid.dart` lost its imports of `photo_dao.dart` and
  `thumbnail_service.dart` when the year scrubber was extracted, so `PhotoFilter`
  and `ThumbnailService` were undefined.
- `db_pragma_test.dart` had a raw string containing an escaped quote, which Dart
  cannot parse.

**Why my checks missed it.** Every structural check I had verified that imports
*resolve* — that the file named exists. None verified that a symbol actually
arrives. Those are different questions and only the second one fails a build.

**The fix that matters.** `tools/check_symbols.py`: for each file, find
identifiers declared at column 0 somewhere in `lib/`, and fail if the file uses
one it cannot see. Column 0 only, because matching indented lines turns every
local variable into a false positive. Verified by deleting the import it was
written for and watching it fail. Wired into CI ahead of `flutter analyze`,
because it names the file and the missing import directly.

**Also in this release**

- `bin/lumen.dart`: the headless CLI — `scan`, `roots`, `add-root`, `stats`,
  `search`, `recent`, `compact`. Pure Dart, so `dart compile exe` builds one
  native binary. Released alongside the app from the same tag, as two extra
  assets.
- `CacheCompactor` and a Reclaim space dialog: finds thumbnails whose photo is
  gone and frees the disk. Thumbnails are derived and rebuildable, so this never
  touches a photo.
- `database.dart` no longer imports `path_provider` — that Flutter plugin was
  what made the whole core unbuildable outside the engine. It now takes a path.
- `PhotoDao` no longer imports the image-format registry, which pulled in
  `dart:ui`. Indexing rules live in `extension_index.dart`, with a test that
  fails if the plugins and the indexer ever disagree.

## 1.7.0 - four more performance wins, no new surface

Nothing added, nothing removed from the interface. Four places where the app was
doing more work than the result needed.

- **Tiles decoded at the size they are drawn.** The thumbnail is 480 px and a
  tile is 100-300, so every visible tile was decoding roughly ten times the
  pixels it could show, and the image cache held them at full size. `cacheWidth`
  is now the tile extent times the device pixel ratio. Less to decode is also
  faster than decoding more and scaling down.
- **Keep-alives off in the grid.** Nothing in a tile holds state worth
  preserving off screen, and a keep-alive pins the widget and its decoded image
  in memory. `addAutomaticKeepAlives: false`.
- **EXIF read window halved, 512 KB to 256 KB.** The APP1 segment sits inside
  the first 64 KB of a normal JPEG. Across a 50,000-photo first scan the old
  window meant up to 25 GB of reads for metadata that was not there. Files with
  anything past the window fall back to the filename date, which is what that
  chain is for.
- **Duplicate groups fetched in one query.** The screen called `byId` once per
  group member — N platform round trips per group. New `PhotoDao.byIds` chunks
  at 400 so it also stays inside SQLite's bound-variable limit, with a test that
  crosses the boundary at 420 rows.

## 1.6.9 - widget tests, and a rail that could overflow

Three of the four bugs you photographed were layout defects found by a human
looking at a screen, because CI only compiled. This closes that gap.

- **`YearScrubber` extracted and fixed.** It was a `Column` of year labels with
  no bound: a library spanning thirty years wanted thirty labels, which is taller
  than the screen, and it would have overflowed. Labels are now thinned to what
  fits, keeping the newest year — the one people reach for.
- **`MonthHeaderDelegate` extracted** so the pinned header can be pumped in a
  `CustomScrollView` and asserted, including that it stays pinned after its group
  scrolls away.
- **Three new widget test files** — year scrubber (thinning, short window, tap to
  seek), month header (renders, stays pinned, long label at 320 px) and the
  support dialog (all six handles at phone width, narrow window, the "nothing is
  gated" line). A `RenderFlex` overflow throws in a widget test, so each of these
  is a real regression guard rather than a smoke test.

21 test files now. Still no widget test for the viewer or the grid as a whole —
both need providers and a database, which is a bigger harness.

## 1.6.8 - EXIF parsing moved off the UI isolate

The last big performance item, done in the smallest shape that could work.

- **What was blocking.** The walk, `stat` and directory listing are async I/O and
  were never the problem. Reading up to 512 KB per file and parsing the TIFF
  structure is pure CPU on the UI isolate, and that is what made a first scan of
  a phone library stutter.
- **The shape.** `Isolate.run` per batch of 150 files. It spawns, runs and tears
  down one isolate per batch - about a millisecond against the hundreds a batch
  of EXIF reads costs. A long-lived worker with a message protocol would save
  that millisecond and add a state machine to maintain; this does not.
- **Why not one isolate for the whole scan.** sqflite cannot cross an isolate
  boundary, so the writing has to stay on the main isolate regardless. The split
  is therefore exactly at the boundary the database already forces.
- **Fallback.** If `Isolate.run` throws, the same function runs inline, so a
  platform that refuses isolates still completes a scan.
- New `scan_worker.dart` holds `PendingFile` and `readCandidates` — plain fields
  and no database, so it is safe to send. Three tests cover it directly.

## 1.6.7 - face boxes, the Android folder picker, and a test that bites

- **Face tags ignored rotation.** Boxes are stored in the image's own
  coordinates, because that is what the file contains, but the viewer draws the
  photo rotated - so on a turned photo the box landed on somebody's elbow. New
  `BoxRotation` maps a box both ways, with eight tests including round trips and
  frame containment. Drawing uses `toDisplay`, storing uses `fromDisplay`.
- **"Add folder" was a dead end on Android.** The system picker hands back a
  content URI, which `dart:io` cannot read, so the folder was added and could
  never be opened. It is now hidden on Android with an explanation and the
  standard-folders route offered instead. Desktop keeps the picker.
- **Fuzzy search scanned 8,000 file names per keystroke.** Capped at 2,000.
- **`FormatTile` extracted and tested.** Every layout bug so far was found by a
  phone screenshot, not by CI. A `RenderFlex` overflow throws in a widget test,
  so pumping this row at 1080x2340 with an eighteen-extension plugin now fails
  the build if the overflow returns. That is the first widget test in the repo
  and it guards the specific defect you photographed.

## 1.6.6 - zoom, and the capture-date fallback

**Zoom was broken in four ways**, all in the viewer's `InteractiveViewer`:

- **Panning a zoomed photo swiped to the next one.** A horizontal drag was
  claimed by the surrounding `PageView`. The pager is now locked while zoomed,
  so a drag belongs to the photo.
- **The zoom was computed against the wrong box for rotated photos.** The
  `AspectRatio` used the unrotated dimensions, so a quarter-turned photo sat in a
  frame of the wrong shape and every pan felt off. The aspect now swaps for
  90°/270°.
- **No double-tap.** Added: double-tap zooms to 2.6x about the tapped point,
  double-tap again returns to fit.
- **Zoom survived leaving the page**, so coming back found the photo still
  magnified and off-centre. It now resets when the page goes inactive.

Also fixed: face-tag coordinates were normalised against a `_imageBox` field
written by *every* page during build, so with mixed aspect ratios the box
belonged to a neighbour. The box is now captured per gesture.

**Capture date now falls back properly.** EXIF → the date in the file name →
mtime. `IMG_20240115_183022`, `PXL_…`, `Screenshot_20240115-…` all carry one, and
on Android mtime is the copy date, which is what collapsed the library into a
single month. New `CaptureDate` with its own tests; midday is used when the name
has no time, so the day survives a negative-offset timezone.

**Three more performance fixes:**

- `controller.photos` returned `List.unmodifiable(...)` — a full copy of the
  loaded page on every access, several times per build. Now an
  `UnmodifiableListView`, which is O(1) and still read-only.
- `dateBuckets()` ran on every refresh and nothing ever read the result. Removed
  from the refresh path.
- Thumbnail concurrency was hardcoded to 3. It now scales with the core count,
  capped at 6 — three decoders on a two-core phone compete with the UI thread.
- The viewer decoded at a fixed 2400 px. Now 1.5x the device pixel width, floored
  at 1080, which roughly halves peak bitmap memory on a 1080p phone.

## 1.6.5 - deep audit: the scanner was doing it the slow way

Five defects, four of them performance, found by reading the hot paths instead
of reacting to a screenshot.

- **The scanner ran one SQL query per file.** `byPath()` inside the walk loop, so
  a 50,000-photo library meant 50,000 platform-channel round trips before any
  EXIF was read. It now loads one path-keyed snapshot into memory and every
  "have I seen this?" is a map lookup. This contradicted the README's own claim
  that a rescan takes seconds.
- **The upsert was SELECT, then INSERT or UPDATE, per row** — three round trips
  per file. Now a single `INSERT … ON CONFLICT(path) DO UPDATE`, which also
  preserves the row id, so ratings, albums, faces and edits survive a rescan.
  (The old code was already correct on that point; the new one keeps it and is
  faster.)
- **Vanished files cost 50,000 sequential `File.exists()` calls** at the end of
  every scan. Now one `UPDATE … WHERE path NOT IN (SELECT …)` against a temp
  table filled in chunks of 500, which also sidesteps SQLite's bound-variable
  limit.
- **The grid stat-ed the filesystem on every tile rebuild.** `existsSync` on the
  UI thread, once per visible tile per frame. Now memoised in the thumbnail
  service: one stat per photo, ever.
- **The slideshow never released decoded images.** Every photo shown stayed in
  memory for the whole run. Decodes are now keyed by slide index and evicted
  beyond ±2, disposed after the frame as everywhere else.

One behaviour change worth calling out: "mark vanished" is now skipped entirely
when no root directory existed, because an unmounted drive and an empty library
look identical from inside the walk. Previously an unplugged drive would have
marked the whole library missing. There is a test for it.

## 1.6.4 - pinned month headers

The library showed no dates at all while scrolling.

- The header was a `SliverToBoxAdapter`, which scrolls away with its group. With
  a handful of large month groups - 131 photos can be two or three months - the
  label is off screen for almost the entire library. That is not a rendering
  bug, it is the wrong widget: a date you can only see at the top of a
  66-row group is not a date.
- Headers are now `SliverPersistentHeader(pinned: true)`: the month stays at the
  top while you scroll through its photos, the way Picasa did it. Fixed 44 px
  height, opaque background so tiles pass underneath, hairline divider.
- The year rail's scroll-offset estimate reads that height from one constant, so
  the two cannot drift.

## 1.6.3 - what the Android screenshots showed

The app runs. Four defects were visible on a real phone that no desktop build
could have shown.

- **The image-format rows overflowed.** A `ListTile` title built from a `Row`
  with an unbounded extension label: the RAW plugin claims eighteen extensions,
  the row ran off the screen, and `Flexible` squeezed the plugin name to one
  character per line - visible as stacked "a m e" and "A R A" behind the support
  dialog. Now a padded row with an `Expanded` column, so text wraps instead of
  overflowing. Long extension lists are also capped at six plus "+N more".
- **The year rail covered the last column.** It was a `Stack` overlay, so the
  rightmost tile in every row was partly untappable and the year labels sat on
  top of photos. It now occupies its own column, and the column count is
  recomputed for the narrower width.
- **Settings printed a hardcoded "1.0.0"** while the release was 1.6.1. Worse
  than printing nothing: it tells whoever reports a bug the wrong build. The
  version now comes from `--dart-define=APP_VERSION`, injected from the tag in
  the release workflow.

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
