#!/usr/bin/env python3
"""Scaffold a freshly built app into the estate's presentation layout.

It does the mechanical part of the method in one pass, and nothing else:

  docs/<everything>        -> docs/play/<everything>   (assets/ stays where it is)
  docs/index.html          -> the landing page, from assets/landing-skeleton.html
  the support block        -> pasted into the footer and into the app's header
  docs/assets/             -> upi-qr.svg and support-portrait.jpg generated

The design is still yours: the skeleton keeps its {{placeholders}}, so what you
replace is the palette, the copy and the motif, not the plumbing.

  python3 tools/scaffold.py . --app-name Thermals --slug thermals \
      --live https://drsamonline.github.io/app-thermals \
      --repo-url https://github.com/drsamonline/app-thermals

  python3 tools/scaffold.py . --dry-run      # show the plan, touch nothing

Needs assets/landing-skeleton.html, assets/support-block.html and
assets/support-portrait.b64 beside it (in tools/assets/, or the skill's assets/).
"""
import argparse
import datetime
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

ASSET_DIRS = [
    os.path.join(HERE, "assets"),
    os.path.join(HERE, os.pardir, "assets"),
    HERE,
    os.path.join(HERE, os.pardir),
]
PASTE_COMMENT = re.compile(
    r"<!--\s*PASTE region 1 of assets/support-block\.html here\..*?-->", re.S)


def find_asset(name):
    for directory in ASSET_DIRS:
        path = os.path.normpath(os.path.join(directory, name))
        if os.path.exists(path):
            return path
    return None


def regions(block_html):
    r1 = block_html.split("<!-- support:block:start -->")[1].split("<!-- support:block:end -->")[0]
    r2 = block_html.split("<!-- support:app:start -->")[1].split("<!-- support:app:end -->")[0]
    r2 = r2.replace('<!-- paste region 1 here, with src="../assets/upi-qr.svg" -->', r1)
    r2 = r2.replace('src="assets/upi-qr.svg"', 'src="../assets/upi-qr.svg"')
    r2 = r2.replace('src="assets/support-portrait.jpg"', 'src="../assets/support-portrait.jpg"')
    return r1, r2


def insert_before(body, markers, chunk):
    """Insert chunk before the last occurrence of the first marker that exists."""
    for marker in markers:
        i = body.rfind(marker)
        if i >= 0:
            return body[:i] + chunk + "\n" + body[i:]
    return body + "\n" + chunk


def main():
    ap = argparse.ArgumentParser(description="Scaffold an app into docs/play/ with a landing page.")
    ap.add_argument("repo", help="path to the repository")
    ap.add_argument("--app-name", help="display name, default the repo directory name")
    ap.add_argument("--slug", help="theme storage key suffix, default the repo directory name")
    ap.add_argument("--live", default="", help="live URL, e.g. https://user.github.io/app")
    ap.add_argument("--repo-url", default="", help="source URL")
    ap.add_argument("--hub", default="https://drsamonline.github.io/", help="estate hub URL")
    ap.add_argument("--licence", default="", help="licence as shown in the footer")
    ap.add_argument("--dry-run", action="store_true", help="print the plan, change nothing")
    args = ap.parse_args()

    root = os.path.abspath(args.repo)
    if not os.path.isdir(root):
        sys.exit("not a directory: %s" % root)

    name = args.app_name or os.path.basename(root.rstrip(os.sep))
    slug = args.slug or re.sub(r"[^a-z0-9-]+", "-", name.lower())
    docs = os.path.join(root, "docs")
    play = os.path.join(docs, "play")
    assets = os.path.join(docs, "assets")

    skeleton_path = find_asset("landing-skeleton.html")
    block_path = find_asset("support-block.html")
    missing = [n for n, p in (("landing-skeleton.html", skeleton_path),
                              ("support-block.html", block_path)) if not p]
    if missing:
        sys.exit("missing asset(s): %s — copy the skill's assets/ next to this script" %
                 ", ".join(missing))

    plan = []
    if not os.path.isdir(docs):
        sys.exit("no docs/ directory in %s — build the app into docs/ first" % root)

    already_split = os.path.isfile(os.path.join(play, "index.html"))
    if already_split:
        plan.append("app is already at docs/play/ — nothing to move")
    else:
        movable = [e for e in sorted(os.listdir(docs))
                   if e not in ("assets", "play") and not e.startswith(".")]
        plan.append("move %d entries into docs/play/ (%s)" %
                    (len(movable), ", ".join(movable[:6]) + ("…" if len(movable) > 6 else "")))

    landing_path = os.path.join(docs, "index.html")
    write_landing = not already_split
    plan.append("write the landing page from the skeleton" if write_landing
                else "landing page already exists — leave it alone")
    plan.append("paste the support block: region 1 into the footer, region 2 into the app")
    plan.append("generate docs/assets/upi-qr.svg and docs/assets/support-portrait.jpg")

    if args.dry_run:
        print("PLAN  %s" % root)
        for line in plan:
            print("  · %s" % line)
        print("\n  then: tools/verify.py . --audit   (and replace the {{placeholders}} by hand)")
        try:
            import links as links_mod
            print()
            links_mod.print_links(links_mod.links_for(root))
        except ImportError:
            pass
        return 0

    # 1. the split
    if not already_split:
        os.makedirs(play, exist_ok=True)
        for entry in sorted(os.listdir(docs)):
            if entry in ("assets", "play") or entry.startswith("."):
                continue
            shutil.move(os.path.join(docs, entry), os.path.join(play, entry))
        if not os.path.isfile(os.path.join(play, "index.html")):
            print("warning: docs/ had no index.html — the app entry may be named differently")

    # 2. the landing page
    skeleton = open(skeleton_path, encoding="utf-8").read()
    if write_landing:
        subs = {
            "{{App}}": name,
            "{{live url}}": args.live.rstrip("/"),
            "{{repo}}": args.repo_url,
            "{{hub}}": args.hub,
            "{{slug}}": slug,
            "{{licence}}": args.licence or "{{licence}}",
            "{{build stamp: build YYYY-MM-DD · commit abc1234}}":
                "build %s · commit %s" % (datetime.date.today().isoformat(), "uncommitted"),
        }
        for key, value in subs.items():
            skeleton = skeleton.replace(key, value)

    # 3. the support block
    block = open(block_path, encoding="utf-8").read()
    r1, r2 = regions(block)

    if write_landing:
        if PASTE_COMMENT.search(skeleton):
            landing = PASTE_COMMENT.sub(lambda _m: r1, skeleton, count=1)
        else:
            landing = insert_before(skeleton, ["</footer>", "</body>"], r1)
        os.makedirs(assets, exist_ok=True)
        with open(landing_path, "w", encoding="utf-8") as fh:
            fh.write(landing)

    app_path = os.path.join(play, "index.html")
    if os.path.isfile(app_path):
        app = open(app_path, encoding="utf-8").read()
        if "support-open" in app or "data-support" in app:
            print("support button already in the app — left alone")
        else:
            with open(app_path, "w", encoding="utf-8") as fh:
                fh.write(insert_before(app, ["</body>", "</html>"], r2))

    # 4. the assets that carry no judgement
    os.makedirs(assets, exist_ok=True)
    try:
        import support_portrait
        path, written = support_portrait.write_portrait(assets)
        print("%s %s" % ("wrote" if written else "already right:", os.path.relpath(path, root)))
    except Exception as exc:  # noqa: BLE001
        print("portrait: skipped (%s)" % exc)
    try:
        import support_qr
        path, uri = support_qr.write_qr(os.path.join(assets, "upi-qr.svg"))
        print("wrote %s" % os.path.relpath(path, root))
        print("  its intent is %s" % uri)
    except Exception as exc:  # noqa: BLE001
        print("upi-qr: skipped (%s)" % exc)

    print("\nSCAFFOLDED  %s" % root)
    print("  next: replace the {{placeholders}} in docs/index.html — that is the design work")
    print("        tools/badges.py --tests \"N passing\" --licence \"…\"")
    print("        tools/shot.sh . landing && tools/shot.sh . app app \"#/<populated route>\"")
    print("        tools/verify.py . --audit")

    try:
        import links as links_mod
        print()
        links_mod.print_links(links_mod.links_for(root))
    except ImportError:
        print("\n(copy links.py next to this script to get the clickable links)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
