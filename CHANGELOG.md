# Changelog

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
