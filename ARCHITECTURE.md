# Architecture

## Shape

```
lib/
  main.dart              platform bootstrap, SQLite factory selection
  app.dart               theme, first-run routing
  core/
    app_paths.dart       one writable directory, thumb sharding
    settings.dart        SharedPreferences (behaviour, not data)
    models/              Photo, Album, Person, Face, EditRecipe
    db/                  AppDatabase + one DAO per aggregate
    scan/                EXIF reader, scanner, thumbnails, watcher, exporter
    lan/                 HttpServer, web gallery page, UDP beacon
  state/                 Riverpod providers + ChangeNotifier controllers
  ui/                    screens and widgets
```

Three layers, strictly one-directional: `ui -> state -> core`. Nothing in
`core` imports Flutter widgets, so the whole engine is unit-testable without a
render surface — which is what `test/db_test.dart` does.

## The index

One SQLite file. Ten tables:

| table | purpose |
|---|---|
| `photos` | one row per image file, with EXIF columns inlined |
| `photos_fts` | FTS5 virtual table over name/folder/caption/tags |
| `library_roots` | folders to walk |
| `albums`, `album_photos` | virtual collections |
| `people`, `faces` | named people and normalised face boxes |
| `edits` | one JSON recipe per edited photo |
| `scan_log` | scan history, for the "last indexed" line |

EXIF columns are inlined into `photos` rather than normalised into a separate
table. A camera model repeats tens of thousands of times, but a join on every
grid page costs more than the duplication does. This is the right trade at
personal-library scale (up to a few hundred thousand photos).

### Why WAL

`journal_mode=WAL`, `synchronous=NORMAL`. WAL lets the scanner write while the
grid reads, without the reader blocking. NORMAL risks losing the last
transaction on a power cut — acceptable, because the index is derived data and
a rescan rebuilds it exactly.

### Why FTS5 is optional

Android ships whatever SQLite the OEM chose. FTS5 has been standard since 3.9
(2015), but not universally compiled in. `_tryCreateFts()` attempts the virtual
table and triggers inside a try/catch; on failure `ftsEnabled` stays false and
`PhotoDao` falls back to `LIKE`. The app never fails to start because of a
search feature.

FTS uses the external-content pattern (`content='photos'`) with three triggers,
so the index cannot drift from the table.

## Scanning

The scanner walks each root with `Directory.list(recursive: true)`. For every
file:

1. Skip anything that is not an image extension.
2. `stat()` it.
3. Look up the path. If size **and** mtime match, skip without opening the file.
4. Otherwise read the first 512 KB and parse EXIF.
5. Batch inserts in transactions of 150, yielding to the event loop between
   batches so the UI keeps painting.

Step 3 is what makes rescans fast: a 50,000-photo library that gained 12 files
opens 12 files.

After the walk, `_markVanished` stats only the paths that were **not** touched,
and sets `missing = 1` on the ones that are gone. Nothing is ever deleted
automatically — ratings, albums and edits survive a file being temporarily
unmounted.

## Thumbnails

`ui.instantiateImageCodec(bytes, targetWidth: 480)` downsamples **during**
decode, inside the Flutter engine's native code. Decoding a 24 MP JPEG to 480 px
this way is roughly 5-10x faster than decoding full size and scaling, and it
never touches the UI isolate.

Generated PNGs are written to `thumbs/<id ~/ 1000>/<id>.png` and served straight
from disk by `Image.file`, so Flutter's own image cache does the rest.

Sharding into 1000-id buckets matters on Windows/NTFS and on Android's ext4 —
a single folder with 200,000 entries makes directory operations crawl.

A three-slot queue bounds concurrent generation so a fast scroll cannot spawn
50 simultaneous decodes.

## Non-destructive edits

`EditRecipe` is a value object: rotate, flip, crop rectangle, and four colour
adjustments, all in normalised units. It serialises to ~120 bytes of JSON and
lives in one row.

Rendering composes a 4x5 colour matrix (saturation, warmth, contrast,
brightness, in that order) and hands it to `ColorFilter.matrix`. Crop is a
`Transform.scale` about the crop centre inside a `ClipRect`. Rotation is a
`RotatedBox`.

Because the same widget renders both the 480 px grid tile and the 2400 px viewer
image, the grid cannot disagree with the viewer.

Export re-runs the same maths on a `Canvas` and writes a new PNG — the original
file is opened read-only and never written.

## Tone curves

`ToneCurve` turns control points into a 256-entry lookup table using **monotone
cubic** interpolation (Fritsch-Carlson). A plain spline overshoots between
control points, which on a tone curve appears as a bright ring around a dark
edge — the classic reason a hand-rolled curve tool looks wrong. The limiter step
is what removes it, and there is a test that asserts a deliberately steep curve
never exceeds its control points.

The LUT is applied on the **CPU**, not in a fragment shader:

- the same 256 numbers reach the grid thumbnail, the viewer and the exported
  PNG, so the three cannot drift;
- no asset pipeline, no GLSL, no driver that compiles a shader and draws nothing;
- the cost is tens of milliseconds per render, paid when a photo opens or an
  edit is saved — not sixty times a second.

Curve changes are debounced by 240 ms before re-rendering the preview, so
dragging a point stays smooth.

### Order of operations

The curve is applied to the **source pixels first**, then the colour matrix,
then crop, flip and rotate. The exporter, the viewer and the thumbnail
regenerator all use `Exporter.render`, so the order is defined once. Two code
paths disagreeing about this order is the usual way a photo editor ships a
preview that does not match its export.

### The grid thumbnail

Saving an edit calls `Exporter.regenerateThumbnail`, which decodes the original
at 480 px, runs the full recipe, and overwrites the cached PNG. Without it the
grid would show the unedited photo while the viewer showed the edit — which is
what the code did before this change, and what `ARCHITECTURE.md` wrongly claimed
it did not.

## Places without a map

GPS is stored at index time as two floats. `places()` rounds both to one decimal
(~11 km) and groups in SQL — `GROUP BY ROUND(lat,1), ROUND(lon,1)` — so a place
list costs one scan, not a per-photo loop. Tapping a place filters the grid with
a **bounding box** rather than a radius, because a box is the one shape SQLite
can answer with a range scan on plain columns.

There is no map. Rendering pins needs tiles, tiles need a network, and the app
does not use one. A bundled vector basemap is the roadmap answer, not a tile
fetch.

## Timeline scrubber

The scrubber needs a scroll offset per year, and measuring real slivers is
impossible for content that has not been laid out. Instead `_markers()` computes
each year's offset arithmetically: the same column formula the grid delegate
uses (`ceil(usable / (extent + spacing))`), multiplied by the known tile height
and header height. That lands within a row, which is invisible when the target
is a year, and costs nothing.

## Selection and bulk edits

Selection lives inside `PhotoGrid`, not in a global provider. The library and
album grids are both alive inside an `IndexedStack`, so a shared selection would
leak between them — a photo selected in Albums would still be selected when the
user switched back to Library. Keeping the `Set<int>` in the widget's own state
makes that impossible.

Bulk mutations go through `setRatingMany` / `setFavoriteMany`, which build one
`UPDATE ... WHERE id IN (...)` inside a single transaction. Marking 400 photos
is one write, not 400.

## Crop

`CropMath` is pure geometry over `dart:ui` types with no widget dependency, so
the fiddly part is unit-tested without a render surface: corner dragging, aspect
locking, clamping, minimum size, and dragging a corner past its opposite anchor.

Two rules earn their comments in the source:

- A corner **never crosses its anchor**, so a rectangle cannot invert mid-drag.
- With an aspect lock the ratio is satisfied *first*, then the result is pulled
  back inside the frame. Doing it the other way round silently turns a 1:1 lock
  into 16:9 at the edge of a wide photo.

Crop rectangles are stored normalised (0..1 across the image), which is why one
recipe crops correctly in a 160 px grid tile, a 2400 px viewer and a
full-resolution export.

## Image formats

`ImageFormatPlugin` is the whole contract: which extensions it claims, which
open-source library backs it, what the user must install, and how to decode to a
`ui.Image`.

`ImageFormatRegistry` builds an extension → plugin index once, with **first
claim wins**, so the engine's native formats always take the fast in-process
path and a later plugin cannot accidentally shadow them. The scanner, the
thumbnailer, the viewer, the exporter and the LAN server all ask the registry;
none of them inspects a file suffix. Adding a format is one entry in
`defaultPlugins()`.

Two plugin kinds ship:

- `EngineImagePlugin` — the Flutter engine. Downsamples during decode, always
  available, `browserSafe`.
- `ExternalDecoderPlugin` — runs an open-source project's own CLI
  (`heif-convert`, `darktable-cli`, `djxl`, `magick`) against a temp file and
  decodes the PNG it writes.

The CLI binding was chosen over FFI deliberately: no compilation, no per-platform
build, and a mismatched shared library cannot crash the app — the worst case is
a failed process. The cost is one spawn per *new* file, which is bounded because
thumbnails are generated once and cached. `probe()` is cached per plugin, so the
settings screen does not spawn a process per frame.

One safety rule is encoded here rather than in documentation: ImageMagick 6's
binary is called `convert`, which on Windows is also the FAT-to-NTFS tool. That
candidate is never offered on Windows.

## Duplicate detection

A 64-bit dHash per photo, computed from the 480 px thumbnail that already exists
— so the scan reuses work the grid already paid for. The grid is sampled from
the **centre square**, which makes the hash independent of aspect ratio and
guarantees every photo yields exactly 64 bits.

Grouping is not all-pairs. The hash is split into four 16-bit bands and photos
are bucketed by band; only photos sharing a band are compared, and each pair is
verified by Hamming distance. That turns O(n²) into roughly O(n·k) for the
candidate set, so 100,000 photos is still interactive.

Union-find collapses transitive matches (A≈B, B≈C ⟹ A, B, C one group). The
service is read-only by design — see `ROADMAP.md` for why deletion stays manual.

## Export

Two paths, both writing a **new** file:

- **Edited copy** — the same colour matrix and crop maths as the viewer, run on
  a `Canvas`, encoded to PNG. Re-encoding through a canvas cannot carry EXIF, but
  "cannot" is a claim, so `MetadataCheck` then re-opens the written file and
  walks its PNG chunks (or JPEG markers) looking for `eXIf`, `tEXt`, `iTXt`,
  `zTXt`, `tIME`, APP1/APP2/APP13 and COM. The UI reports what was measured.
- **Album ZIP** — store-only, because photos are already compressed. Written
  through an `IOSink` with only the central directory held in memory, so a 4 GB
  album does not need 4 GB of RAM.

## Search

`PhotoDao.search()` returns a `SearchMode` alongside the rows, because a photo
library that silently shows approximate results as if they were exact is worse
than one that finds nothing. The order is exact (FTS5) → substring (`LIKE
%token%`, which is what catches a word in the middle of a filename) → one-edit
tolerance over the newest 8,000 file names (bounded, because scoring a 500k-name
library on every keystroke would stall the UI).

## LAN serving

`HttpServer.bind(InternetAddress.anyIPv4, port)`. Four routes:

- `/` — the gallery page, one self-contained HTML string
- `/api/photos?offset&limit` — JSON page
- `/thumb/<id>` — cached PNG
- `/photo/<id>` — the original file, streamed with `openRead().pipe()`

`openRead().pipe()` never loads a file into memory, so serving a 60 MB TIFF
costs the same as serving a 2 MB JPEG.

Discovery is a UDP broadcast to `255.255.255.255:5354` every five seconds. That
is deliberately dumber than mDNS: mDNS resolution is inconsistent across
Windows, Linux and Android, and a 90-byte JSON broadcast is not.

## Offline guarantee

This is a hard architectural constraint, not a policy:

- No HTTP client package is in `pubspec.yaml`.
- `HttpServer` binds; nothing dials out.
- `RawDatagramSocket` broadcasts; nothing resolves a hostname.
- `test/offline_guard_test.dart` greps `lib/` for `package:http`, `dio`,
  `HttpClient(`, `Socket.connect`, `InternetAddress.lookup` and friends, and
  fails the build if any appear.

## State

Riverpod, with `ChangeNotifier` controllers. The grid's paging window lives in
`LibraryController`; a widget rebuild never re-queries SQLite. Album, person and
search views get their own scoped controller through a `family` provider, keyed
by album id, person id, or the value-equal `PhotoFilter`.

`PhotoFilter` implements `==`/`hashCode` precisely so it can be a provider key
without spawning a controller on every rebuild.
