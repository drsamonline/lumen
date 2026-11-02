# Credits

Lumen is part of the drsamonline fleet, and it borrows deliberately rather than
reinventing. This file records what came from where, so a later change can be
traced back to the thing it was ported from.

## Ported into Lumen

| Feature | From | What was actually taken |
|---|---|---|
| **Duplicate detection** — 64-bit dHash, banded candidate lookup, union-find grouping, keep-best | `ml-kit` (k-NN / k-means "items like this one"), and the hashing approach in `app-image-toolkit` | The idea that offline similarity must run from scratch, on-device, with no model file. The algorithm is new Dart (`lib/core/scan/hash_service.dart`, `duplicate_service.dart`); nothing was copied. |
| **Verified metadata stripping** | `app-image-toolkit` — its *"check"* step, which reads the **output** bytes back and reports what is left | The rule that "stripped" must be measured on the written file, not assumed from the code path. Implemented as `lib/core/export/metadata_check.dart` (PNG chunk and JPEG marker scanners). |
| **Three-stage search** — exact → substring → one-edit tolerance | `search-kit` — inverted index with prefix and fuzzy (edit-distance 1) matching | The ordering: try the precise answer, then widen, and never silently pass approximate results off as exact. `lib/core/search/fuzzy.dart` is a single-pass within-one-edit test rather than a full Levenshtein matrix, because that is the only question the UI asks. |
| **Album → ZIP, store-only, streamed** | `export-kit` — "bundle files into a store-only ZIP" | The decision not to DEFLATE already-compressed photos, and the streaming shape so a large album is bounded by disk, not RAM. `lib/core/export/zip_writer.dart`. |
| **LAN host pattern** — serve the library, print the addresses, browse from a plain browser on the same Wi-Fi | `app-lantern` | The product shape of the LAN feature, and the "no internet at any point" framing. Lumen's host is Dart (`lib/core/lan/`), not Node. |

## Read, but not taken

- **`darktable`** — the RAW development pipeline. Demosaicing needs libraw as a
  native binding; it is on the roadmap, not in v1.
- **`coil`, `glide`, `fresco`** — Android-only image loaders. Flutter's engine
  already downsamples during decode (`instantiateImageCodec` with a target
  width), so adding one would have bought a dependency and no speed.
- **`web-kit`** — the EN/HI/GU i18n layer. Lumen is English-only for now; the
  pattern is the right one to adopt when the strings are finalised.
- **`art-kit`** — median-cut quantisation. A "dominant colour" smart album is a
  good future use; nothing in v1 needs it.
- **`lan-kit`, `crypto-kit`, `optical-kit`, `srs-kit`, `book-kit`, `case-kit`,
  `repertory-kit`, `frame-kit`, `profile-kit`** — no overlap with a photo library.

## Licence

PolyForm Noncommercial 1.0.0, matching the rest of the fleet. The kits above are
MIT; nothing was copied from them, but the debt is recorded anyway.
