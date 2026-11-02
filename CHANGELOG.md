# Changelog

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
