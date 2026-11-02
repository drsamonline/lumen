# Roadmap

Ordered by how much each one changes daily use, not by how fun it is to build.

## Milestone 1 — finish the daily loop (next)

- **Duplicate detection.** Content hash on index (there is a `content_hash`
  column waiting), then a "Duplicates" view with keep-best. Every long-lived
  photo library has thousands.
- **Batch operations.** Multi-select in the grid, then rate / favourite / add to
  album / export for the whole selection.
- **Interactive crop.** The current crop is a square preset; a real crop handle
  overlay with aspect lock is the missing piece of the editor.
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
- **RAW support.** `darktable`-style demosaicing via a native libraw binding —
  this is the one place the referenced darktable repo genuinely helps.
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
