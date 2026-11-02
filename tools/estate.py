#!/usr/bin/env python3
"""One table for the whole estate: which apps still need what.

Adding a support block to a dozen existing repos is where things get missed, so
this walks the sibling repos, inspects each with the same rules as
`verify.py`, and prints one table.

  python3 tools/estate.py ~/code                      # every repo under ~/code
  python3 tools/estate.py ~/code --only 'app-*'       # just the apps
  python3 tools/estate.py ~/code --json > estate.json

Columns are the surfaces that matter: landing page, app, badges, screenshots,
README support section, the support block, the portrait, theme inheritance, and
offline honesty. A dash means the surface is not there at all.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

try:
    from verify import inspect, surface_rows
except ImportError:  # pragma: no cover - only if verify.py was not copied alongside
    sys.exit("verify.py must sit next to estate.py — copy both into the repo's tools/")

MARK = {"pass": "ok", "warn": "warn", "fail": "FAIL", "missing": "-"}
COLUMNS = ["landing", "app", "badges", "shots", "readme", "support", "portrait", "theme",
           "offline", "platforms"]


def looks_like_repo(path):
    return os.path.isdir(os.path.join(path, "docs")) or os.path.isdir(os.path.join(path, ".git"))


def main():
    ap = argparse.ArgumentParser(description="Inspect every repo in a directory and print one table.")
    ap.add_argument("parent", help="directory holding the repos")
    ap.add_argument("--only", help="shell-style pattern the repo name must match, e.g. 'app-*'")
    ap.add_argument("--links", action="store_true",
                    help="after the table, print the README, landing page and app link for each repo")
    ap.add_argument("--check", action="store_true", help="with --links, ask each URL whether it answers")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    parent = os.path.abspath(args.parent)
    if not os.path.isdir(parent):
        sys.exit("not a directory: %s" % parent)

    import fnmatch

    repos = sorted(
        name for name in os.listdir(parent)
        if not name.startswith(".")
        and os.path.isdir(os.path.join(parent, name))
        and looks_like_repo(os.path.join(parent, name))
        and (not args.only or fnmatch.fnmatch(name, args.only))
    )
    if not repos:
        sys.exit("no repos found under %s%s" % (parent, " matching %r" % args.only if args.only else ""))

    reports = []
    for name in repos:
        report = inspect(os.path.join(parent, name))
        reports.append((name, report))

    if args.json:
        print(json.dumps(
            [{"repo": name, "surfaces": dict(surface_rows(report)),
              "fails": report["fails"], "warns": report["warns"]} for name, report in reports],
            indent=2))
        return 0

    width = max(len("repo"), max(len(n) for n, _ in reports))
    colw = max(len(c) for c in COLUMNS) + 2
    head = "  ".join(["%-*s" % (width, "repo")]
                     + ["%-*s" % (colw, c) for c in COLUMNS] + ["fails"])
    print(head)
    print("-" * len(head))

    for name, report in reports:
        cells = ["%-*s" % (colw, MARK[status]) for _, status in surface_rows(report)]
        print("  ".join(["%-*s" % (width, name)] + cells + ["%d" % report["fails"]]))

    broken = [(n, r) for n, r in reports if r["fails"]]
    blockless = [n for n, r in reports
                 if dict(surface_rows(r)).get("support") in ("missing", "fail")]
    print()
    print("%d repos · %d with failing checks · %d without the support block"
          % (len(reports), len(broken), len(blockless)))

    if blockless:
        print("Next: %s" % ", ".join(blockless))
        print("Per repo: tools/verify.py . --audit, then --fix, then paste the block where it is missing.")
    if broken:
        print("Failing: %s" % ", ".join(n for n, _ in broken))

    if args.links:
        try:
            import links as links_mod
        except ImportError:
            print("\nlinks: skipped — copy links.py next to estate.py")
            return 1 if broken else 0
        for name, report in reports:
            print()
            links_mod.print_links(links_mod.links_for(report["repo"]), args.check)
    else:
        print("\nAdd --links to get the README, landing page and app demo URLs for each repo.")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
