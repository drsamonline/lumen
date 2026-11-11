# Lumen

[![tests](docs/assets/badge-tests.svg)](https://github.com/drsamonline/lumen/actions/workflows/test.yml)
[![licence](docs/assets/badge-licence.svg)](LICENSE)
[![offline](docs/assets/badge-offline.svg)](#offline-enforced)
[![build](docs/assets/badge-build.svg)](#building-it)

**A photo library that never phones home.**

An offline library in the spirit of Picasa. Point it at the folders you already
keep your photos in; it reads them, indexes them, and computes everything else —
thumbnails, edits, faces, albums, duplicates — on your machine.

[Live demo](https://drsamonline.github.io/lumen/) ·
[Landing page](https://drsamonline.github.io/lumen/) ·
[The rule](#offline-enforced) ·
[Support](#support)

<!-- shot:start -->

![Lumen's LAN gallery: a grid of photos with star ratings, edited badges and a possible-duplicates strip](docs/assets/app-desktop.png)

<!-- shot:end -->

---

## What it does today (v1)

**Library**
- Folder indexing with incremental rescans — a file whose size and mtime are
  unchanged is never re-opened, so rescanning 50,000 photos after adding one
  folder takes seconds.
- Month-grouped timeline grid, exactly Picasa's rhythm, with a thumbnail-size
  slider from 100 to 300 px.
- Sort by capture date, index date or file name.
- Star ratings (0-5) and favourites, both filterable.
- Background folder watching: drop files in and they appear.

**Metadata**
- EXIF read at index time: capture date, camera make/model, ISO, aperture,
  shutter, focal length, GPS, orientation.
- The full details strip in the viewer.
- GPS is captured and stored. There is no map yet (see the roadmap) because
  map tiles are an internet feature and this app does not use the internet.

**Viewer**
- Swipe, pinch-zoom, per-photo details.
- Non-destructive editing: rotate, flip, brightness, contrast, saturation,
  warmth, a real crop tool (corner handles, rule-of-thirds guides, Free / 1:1 /
  4:3 / 3:4 / 3:2 / 16:9 presets), and a **tone curve** with draggable points and
  six presets. Stored as a small JSON recipe in SQLite; the original file is
  never modified.
- Saving an edit also re-renders the cached grid thumbnail, so the tile shows
  what the viewer shows.
- Export an edited copy as a real PNG beside the original.

**Browse**
- Month-grouped timeline with a year scrubber down the right edge — drag it to
  jump to any year, which is the only navigation that works at 10,000 photos.
- Slideshow mode: full screen, auto-advance at 3/5/8/15 s, arrows to step, space
  to pause, Escape to leave. Reachable from the library or from any photo.
- Places: photos grouped by rounded GPS coordinate, largest group first. No map,
  because map tiles are an internet feature — but the browsing people actually
  did with Picasa's Places survives.

**Multi-select**
- Long-press any photo to start selecting; tap to add or remove.
- One action bar for the whole selection: 0-5 stars, favourite / unfavourite,
  add to album, or export as a ZIP.
- Bulk edits run in a single transaction, so rating 400 photos is one write.

**People**
- Manual face tagging: drag a box on a photo, name the person. Face boxes are
  stored as normalised coordinates, so they stay correct at any resolution.

**Albums**
- Virtual albums. A photo can be in many; nothing is copied.

**Search**
- SQLite FTS5 over file name, folder, caption and tags, with a LIKE fallback on
  platforms whose SQLite lacks FTS5.
- Three-stage fallback so a search rarely returns nothing: exact, then substring
  ("each" finds "beach-sunset.jpg"), then typo-tolerant ("reciept" finds
  "receipt.jpg"). The bar says which stage answered, rather than quietly showing
  approximate results as if they were exact.
- Filter chips for favourites and star ratings.

**Image formats**
- Nothing about formats is hardcoded. Every format is a plugin, and the scanner,
  thumbnailer, viewer and LAN server all ask the registry rather than testing a
  suffix — so installing a decoder makes its formats indexable with no code
  change.
- **Built in, always:** JPEG, PNG, WebP (still and animated), GIF, BMP, WBMP.
- **Via open-source decoders, when installed:** HEIC/HEIF/AVIF (libheif,
  libavif), TIFF (libtiff), camera RAW — CR2, CR3, NEF, ARW, DNG, RAF, RW2, ORF,
  PEF and more (LibRaw, darktable), JPEG XL (libjxl), and PSD/TGA/DDS/EXR/HDR
  (ImageMagick).
- Settings shows every plugin, whether it is ready, and exactly what to install
  if it is not. Lumen never downloads or bundles a decoder.
- The LAN gallery transcodes formats a browser cannot paint, so a HEIC photo
  still opens on a TV.

**Duplicates**
- Perceptual fingerprints (64-bit dHash) computed from the thumbnails that
  already exist, so a duplicate scan costs one cheap decode per photo.
- Grouping by 16-bit band lookup, then verified by Hamming distance — no
  all-pairs comparison, so 100,000 photos is still fast.
- Each group marks the copy worth keeping (largest pixel count, then largest
  file) and totals the space the extras use. **Lumen never deletes a photo.**

**Export**
- Album → store-only ZIP, streamed straight to disk, so album size is bounded by
  free space rather than RAM.
- Edited copies are written as PNG, and the written bytes are then **read back**
  and scanned for EXIF, XMP, IPTC, PNG text and time chunks. The snackbar says
  "checked: nothing left" only when that is literally true of the file on disk.

**LAN streaming**
- Turn it on in Settings and any browser on your Wi-Fi can browse the whole
  library at `http://<your-ip>:8421` — a self-contained gallery page, no CDN, no
  fonts to fetch, works with the router's WAN port unplugged.
- A UDP beacon broadcasts the address so a phone can find the desktop.

**Offline, enforced**
- No `http`, no `dio`, no webview, no telemetry. `test/offline_guard_test.dart`
  fails the build if anyone adds an outbound network client.

---

## Borrowed from the rest of the estate

Lumen is the first non-web app in this fleet, but four of its features are
direct ports of ideas already solved elsewhere in it. `CREDITS.md` lists exactly
which repo each came from and what was actually taken.

---

## Building it

You need the Flutter SDK (3.27 or newer — Dart 3.6+).

```bash
cd lumen

# 1. Generate the platform folders (android/, windows/, linux/)
flutter create --platforms=android,windows,linux .

# 2. Fetch packages
flutter pub get

# 3. Run on whichever platform you are sitting in front of
flutter run -d windows      # or: linux
flutter run -d <device-id>  # Android
```

`tool/setup.sh` (Linux) and `tool/setup.ps1` (Windows) do steps 1 and 2 in one
go.

### Shipping builds

```bash
flutter build windows --release
flutter build linux --release
flutter build apk --release --split-per-abi
```

### Android notes

`flutter create` writes a manifest without storage permissions. Lumen needs to
read image files, so add these to `android/app/src/main/AndroidManifest.xml`
inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
<!-- Required only to bind the local LAN server. No outbound use. -->
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```

Also set `android:usesCleartextTraffic="true"` on `<application>` — the LAN
gallery is plain HTTP on your own network, and nothing else in the app makes a
request at all.

On first run, tap **Use camera roll** on the setup screen; it adds
`/storage/emulated/0/DCIM`, `Pictures` and `Download` automatically.

---

## Tests

CI runs on every push (`.github/workflows/test.yml`): `flutter analyze`, then
`flutter test`, then three real compiles — Linux desktop, Windows desktop and an
Android APK. That is the evidence behind "one codebase, three platforms" — every
target this project claims is compiled on every push.

Locally:

```bash
flutter test
```

- `test/edit_recipe_test.dart` — the colour-matrix maths, JSON round-trips,
  garbage input.
- `test/db_test.dart` — indexing, paging, filters, FTS search, month buckets,
  albums, edit persistence.
- `test/offline_guard_test.dart` — proves no outbound network client exists.
- `test/format_registry_test.dart` — extension routing, plugin precedence, and
  that every shipped plugin declares its backing library and its requirement.
- `test/hash_test.dart`, `test/fuzzy_test.dart`, `test/zip_test.dart`,
  `test/metadata_check_test.dart` — the v1.1 feature logic.
- `test/crop_math_test.dart`, `test/batch_ops_test.dart`, `test/places_test.dart`
  — v1.3–v1.4 logic.
- `test/tone_curve_test.dart` — LUT generation, monotonicity, overshoot, LUT
  application, and recipe round-tripping.
- `test/scanner_test.dart`, `test/search_fallback_test.dart` — regressions found
  in the v1.4.1 audit.

---

## Where things live

Everything Lumen writes goes under one application-support directory:

```
<app support>/
  lumen.db          SQLite index (photos, albums, people, faces, edits)
  thumbs/           PNG thumbnails, sharded 1000 ids per folder
  exports/          fallback target for exported copies
```

Your photos are never copied, moved or modified.

---

## Headless CLI

The same index and scanner without the interface. Pure Dart, so it compiles to a
single native binary — `lumen-cli-linux-x64` and `lumen-cli-windows-x64.exe` ship
alongside the app in every release.

```
lumen scan [--root DIR]     index the library
lumen stats                 what the index holds
lumen search QUERY          file names, folders, captions, tags
lumen recent [N]            the N most recent photos
lumen compact [--orphans|--all] [--yes]
lumen --help
```

`--json` on `stats`, `search`, `recent` and `compact` gives stable objects, so
anything that can run a process can consume the library:

```bash
lumen search "harbour" --json | jq -r '.photos[].path'
lumen stats --json | jq .photos
```

The CLI and the app share one index file, so either can rescan what the other
indexed. Both need SQLite 3 available to the dynamic loader — present on most
Linux systems; on Windows put `sqlite3.dll` beside the exe.

### Driving it from a launcher

Any tray launcher or hotkey tool that runs a command can reach the library. In
[CLDR](https://github.com/drsamonline/CLDR) that is one line in
`~/.config/cldr/config.toml`:

```toml
alias.photos = "/run lumen search"
```

Then `/photos harbour` in the command window opens the library's index. Note the
honest limit: CLDR spawns a routed command **detached** and does not render its
stdout, so the results do not appear inside its window — use `--json` and pipe it
somewhere, or open the app itself with `alias.lumen = "/run lumen"`.

## Known limitations

- **The LAN gallery streams originals.** Edits appear in the grid thumbnail and
  in the app's viewer, but a browser on the network sees the unedited file at
  full size. Serving a rendered copy would mean a decode per request; it is on
  the roadmap rather than half-done.
- **Apple platforms are not supported**, permanently. See `ROADMAP.md`.

## Honest status

This is a working v1, not a finished Picasa replacement. What is deliberately
missing, and why, is in `ROADMAP.md`. The two you will notice first:

1. **No automatic face detection.** Face boxes are drawn by hand. Real
   detection needs an on-device ML model, which is a milestone of its own.
2. **No maps.** Picasa's geo view needs map tiles; tiles need the internet.
   The plan is bundled offline tiles or a vector basemap, not a network call.
3. **Duplicate *deletion* is not automated.** Lumen groups and ranks; removing
   the extras stays a manual act, because a wrong automatic delete is the one
   mistake a photo library cannot apologise for.
4. **Video files are not indexed.** Photos only, for now.
5. **Exotic formats need a decoder installed.** JPEG, PNG, WebP, GIF, BMP and
   WBMP work out of the box; HEIC, TIFF, RAW and JPEG XL need their open-source
   tool on `PATH` (see *Image formats* above). That is deliberate — bundling
   libheif and LibRaw would multiply the binary size and the licence surface.
6. **The external decoders are CLI bindings, not FFI.** That keeps the build
   dependency-free and crash-safe, and it works on Windows and Linux. On
   Android there is no shell, so those formats stay unavailable there until an
   FFI plugin is added — the interface is already shaped for one.

## Support

Lumen is free, offline, and has no business model. If it is useful to you:

| | |
|---|---|
| UPI (India) | `drsohilboi@ybl` — payee Dr. Sohil Momin |
| GitHub Sponsors | [github.com/sponsors/drsamonline](https://github.com/sponsors/drsamonline) |
| Ko-fi | <https://ko-fi.com/matneo> |
| PayPal | <https://paypal.me/drsohilmomin?locale.x=en_GB&country.x=IN> |
| Books | <https://www.amazon.com/stores/author/B08ZT331LY/allbooks?ccs_id=aed72b9f-71d9-41dc-adee-e9368a317acc> |
| Everything else | <https://drsamonline.github.io/> |
| Email | <sohilmomin2000@gmail.com> |

The [landing page](https://drsamonline.github.io/lumen/) carries the same handles
with a scannable UPI QR, and the app has a Support button that opens the same
block in the app's own theme. Nothing is gated behind it.
