#!/usr/bin/env python3
"""Generate the repository's badges as local SVG files.

An offline-first app should not depend on an image service to describe itself,
and a landing page that breaks its own promise on the first screen is a bad
joke. These are drawn here, committed, and referenced by relative path — they
render on GitHub Pages, in the README, and from `file://` with no network.

The claims are arguments, not constants: the assertion count and the dependency
count drift, and a badge that lies is worse than no badge.

  python3 tools/badges.py
  python3 tools/badges.py --tests 612 --deps 0 --licence "PolyForm NC 1.0.0"
  python3 tools/badges.py --config tools/badges.json --out docs/assets

A config file wins over the defaults, and an explicit flag wins over the config:

  { "tests": "612 passing", "licence": "MIT", "deps": "0 runtime",
    "live": "online", "build": "green", "offline": "no network",
    "colours": { "ink": "#14110e", "cream": "#f7f2e9", "cold": "#2f6f8f", "warm": "#b5432c" } }
"""
import argparse
import json
import os

DEFAULTS = {
    "live": "online",
    "tests": "567 passing",
    "build": "green",
    "licence": "PolyForm NC 1.0.0",
    "offline": "no network",
    "deps": "0 runtime",
    "colours": {"ink": "#14110e", "cream": "#f7f2e9", "cold": "#2f6f8f", "warm": "#b5432c"},
}

CH = 6.6  # approximate advance width at 11px in a monospace-ish sans


def badge(label, value, colour, ink, cream):
    lw = int(len(label) * CH) + 16
    vw = int(len(value) * CH) + 16
    total = lw + vw
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="22" role="img" '
        'aria-label="%s: %s">'
        '<title>%s: %s</title>'
        '<linearGradient id="s" x2="0" y2="100%%"><stop offset="0" stop-color="#fff" stop-opacity=".08"/>'
        '<stop offset="1" stop-color="#000" stop-opacity=".10"/></linearGradient>'
        '<clipPath id="r"><rect width="%d" height="22" rx="4" fill="#fff"/></clipPath>'
        '<g clip-path="url(#r)">'
        '<rect width="%d" height="22" fill="%s"/>'
        '<rect x="%d" width="%d" height="22" fill="%s"/>'
        '<rect width="%d" height="22" fill="url(#s)"/>'
        "</g>"
        '<g fill="%s" font-family="ui-sans-serif,Segoe UI,Helvetica,Arial,sans-serif" font-size="11" '
        'text-anchor="middle">'
        '<text x="%d" y="15">%s</text>'
        '<text x="%d" y="15">%s</text>'
        "</g></svg>"
    ) % (total, label, value, label, value, total, lw, ink, lw, vw, colour, total,
         cream, lw // 2, label, lw + vw // 2, value)


def main():
    ap = argparse.ArgumentParser(description="Generate local SVG badges for a repo.")
    ap.add_argument("--out", help="output directory, default <repo>/docs/assets")
    ap.add_argument("--config", help="JSON file with the claim values and colours")
    for key in ("live", "tests", "build", "licence", "offline", "deps"):
        ap.add_argument("--" + key, help="value for the %s badge (default: %s)" % (key, DEFAULTS[key]))
    ap.add_argument("--ink", help="label background colour")
    ap.add_argument("--cream", help="label text colour")
    ap.add_argument("--cold", help="colour for the live badge")
    ap.add_argument("--warm", help="colour for the licence badge")
    args = ap.parse_args()

    cfg = json.loads(json.dumps(DEFAULTS))
    if args.config and os.path.exists(args.config):
        with open(args.config, encoding="utf-8") as fh:
            loaded = json.load(fh)
        cfg["colours"].update(loaded.pop("colours", {}) or {})
        cfg.update(loaded)
    for key in ("live", "tests", "build", "licence", "offline", "deps"):
        val = getattr(args, key, None)
        if val:
            cfg[key] = val
    for key in ("ink", "cream", "cold", "warm"):
        val = getattr(args, key, None)
        if val:
            cfg["colours"][key] = val

    ink, cream = cfg["colours"]["ink"], cfg["colours"]["cream"]
    good = cfg["colours"].get("good", "#2e6b45")
    specs = [
        ("live", "live", cfg["live"], cfg["colours"]["cold"]),
        ("tests", "tests", cfg["tests"], good),
        ("build", "build", cfg["build"], good),
        ("licence", "licence", cfg["licence"], cfg["colours"]["warm"]),
        ("offline", "offline", cfg["offline"], ink),
        ("deps", "deps", cfg["deps"], ink),
    ]

    out = args.out or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "assets")
    os.makedirs(out, exist_ok=True)
    for name, label, value, colour in specs:
        path = os.path.join(out, "badge-%s.svg" % name)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(badge(label, value, colour, ink, cream))
        print("wrote", path)


if __name__ == "__main__":
    main()
