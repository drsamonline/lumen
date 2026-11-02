#!/usr/bin/env python3
"""Write the owner's portrait into a repo, as a real JPEG, from the bundled text asset.

The photo travels with this skill base64-encoded (`assets/support-portrait.b64`)
because a skill's files are text; this decodes it into
`docs/assets/support-portrait.jpg`, which is what the support block loads.

  python3 scripts/support_portrait.py                  # -> docs/assets/support-portrait.jpg
  python3 scripts/support_portrait.py --out docs/assets
  python3 scripts/support_portrait.py --force          # rewrite even if unchanged

Idempotent on purpose: if the repo already has the identical portrait, nothing is
written and nothing shows up in the diff.
"""
import argparse
import base64
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CANDIDATES = [
    os.path.join(HERE, os.pardir, "assets", "support-portrait.b64"),
    os.path.join(HERE, "assets", "support-portrait.b64"),
    os.path.join(HERE, "support-portrait.b64"),
]


def load_bytes():
    for path in CANDIDATES:
        if os.path.exists(path):
            with open(path, encoding="ascii") as fh:
                data = base64.b64decode("".join(fh.read().split()))
            if not data.startswith(b"\xff\xd8"):
                raise RuntimeError("decoded bytes are not a JPEG — %s is damaged" % path)
            return data, path
    raise RuntimeError("support-portrait.b64 not found next to this script — "
                       "copy it from the skill's assets/ directory")


def write_portrait(target=None, force=False):
    """Decode the portrait to `target` (a directory or a file path).

    Returns (path, written) — written is False when the file already matched.
    """
    data, src = load_bytes()
    target = target or os.path.join("docs", "assets")
    if os.path.isdir(target) or not os.path.splitext(target)[1]:
        target = os.path.join(target, "support-portrait.jpg")
    os.makedirs(os.path.dirname(target) or ".", exist_ok=True)

    if os.path.exists(target) and not force:
        with open(target, "rb") as fh:
            if fh.read() == data:
                return target, False

    with open(target, "wb") as fh:
        fh.write(data)
    return target, True


def main():
    ap = argparse.ArgumentParser(description="Decode the bundled portrait into the repo.")
    ap.add_argument("--out", help="output directory or file, default docs/assets")
    ap.add_argument("--force", action="store_true", help="rewrite even if the bytes match")
    args = ap.parse_args()

    try:
        target, written = write_portrait(args.out, args.force)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if written:
        print("wrote %s (%d bytes)" % (target, os.path.getsize(target)))
        print("the block expects 72px on the page, circular — the file is a 320px square crop")
    else:
        print("unchanged %s (%d bytes) — nothing to do" % (target, os.path.getsize(target)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
