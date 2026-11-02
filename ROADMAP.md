# Roadmap

Ordered by how much each one changes daily use, not by how fun it is to build.

## Done since v1

- **Multi-select and bulk actions.** Long-press to select, then rate, favourite,
  add to an album or export as a ZIP in one transaction.
- **Interactive crop.** Corner handles with an aspect lock, rule-of-thirds
  guides and six presets — replacing the placeholder square-crop button.
- **Duplicate detection.** 64-bit dHash from the existing thumbnails, banded
  candidate lookup, union-find grouping, keep-best ranking. Read-only: Lumen
  shows the groups and never deletes.
- **Album export as ZIP.** Store-only, streamed to disk.
- **Verified metadata stripping on export.** The written file is read back and
  scanned, so "nothing left" is a measurement rather than a claim.
- **Three-stage search.** Exact → substring → one-edit typo tolerance, with the
  UI reporting which stage answered.

## Milestone 1 — finish the daily loop (next)

- **Curves and levels.** The colour matrix handles linear adjustments; curves
  need a LUT texture. Worth doing properly.
- **Video indexing.** Thumbnail frame extraction via platform codecs, playback
  through `video_player`, and the same timeline treatment.

## Milestone 2 — the two big Picasa features

- **On-device face detection.** A bundled model (MediaPipe or a small ONNX
  detector) run in an isolate over the thumbnail set, clustering unknown faces
  so the user only has to name each cluster once. This is the feature people
  actually remember Picasa for.
- **Offline maps.** Picasa's geo view needs tiles. Options, in order of
  preference: a bundled vector basemap (protomaps `.pmtiles`, ~50 MB for a
  country), a user-supplied tile folder, or a plain "places" list grouped by
  rounded coordinates with no map at all. Never a network tile fetch.

## Milestone 3 — the things Picasa did that people forgot

- **Collages** — the multi-photo grid layouts.
- **Movies** — the auto-generated slideshow with music, rendered locally with
  FFmpeg (bundled, no network).
- **Photo viewer export to folder structure** — "export album as folder tree".
- **Screensaver** — the full-screen slideshow, which is genuinely how a lot of
  people used Picasa.
- **Timeline scrubbing** — drag a year scrubber down the side of the grid.
- **Print layouts** — contact sheets at real paper sizes.

## Milestone 4 — reach and polish

- **iOS.** The codebase already targets it; only the folder-access model needs
  work (photo-library permission instead of a folder picker).
- **RAW as first-class citizens.** Reading RAW works today through
  `darktable-cli` or ImageMagick. What is missing is *developing* one: an
  embedded preview is shown at the camera's JPEG size, and demosaicing at full
  resolution needs an FFI binding to LibRaw rather than a process spawn.
- **FFI decoder plugins.** The `ImageFormatPlugin` interface is already the right
  shape; a `LibHeifFfiPlugin` and a `LibRawFfiPlugin` would make HEIC and RAW
  work on Android, where there is no shell to call.
- **Colour management.** ICC profile awareness, so wide-gamut photos do not
  shift on screen.
- **Accessibility pass.** Screen-reader labels on every tile, full keyboard
  navigation, and a high-contrast theme.
- **Importance-ranked thumbnail pre-generation** — build thumbs for the newest
  2,000 photos first so a fresh library is usable in seconds rather than
  minutes.

## Deliberately not doing

- Cloud sync, accounts, sharing links, "memories" emails. That is the thing
  Picasa was killed for becoming.
- Any feature that requires a network request. If it cannot work on an
  aeroplane, it does not ship.
