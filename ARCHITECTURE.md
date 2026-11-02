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
