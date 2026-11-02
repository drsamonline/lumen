#!/usr/bin/env python3
"""The links to hand over after a change: the README, the landing page, the app.

A repo is only "done" when someone can click through it. This derives the three
URLs from the repo itself — the canonical/og:url on the landing page, and the
git remote — so the report at the end of a rollout is clickable rather than
described.

  python3 tools/links.py .                 # the three links, plus local files
  python3 tools/links.py . --check         # and whether they answer right now
  python3 tools/links.py . --json

Also importable: `from links import links_for, print_links`.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def git_remote(root):
    try:
        out = subprocess.run(["git", "-C", root, "remote", "get-url", "origin"],
                             capture_output=True, text=True, timeout=10)
        if out.returncode == 0:
            return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return ""


def normalise_remote(url):
    """git@github.com:owner/repo.git -> https://github.com/owner/repo"""
    if not url:
        return ""
    m = re.match(r"git@([^:]+):(.+?)(?:\.git)?/?$", url)
    if m:
        return "https://%s/%s" % (m.group(1), m.group(2))
    m = re.match(r"(?:https?|ssh)://(?:[^@/]+@)?([^/]+)/(.+?)(?:\.git)?/?$", url)
    if m:
        return "https://%s/%s" % (m.group(1), m.group(2))
    return ""


def derive_live(repo_url):
    """GitHub Pages convention: owner.github.io/repo, or owner.github.io for the hub repo."""
    m = re.match(r"https://github\.com/([^/]+)/([^/]+)$", repo_url)
    if not m:
        return ""
    owner, name = m.groups()
    if name.lower() == "%s.github.io" % owner.lower():
        return "https://%s.github.io" % owner
    return "https://%s.github.io/%s" % (owner, name)


def links_for(root):
    root = os.path.abspath(root)
    landing = read(os.path.join(root, "docs", "index.html"))
    readme = read(os.path.join(root, "README.md"))

    live = ""
    m = re.search(r"""<meta[^>]+property=["']og:url["'][^>]+content=["']([^"']+)""", landing)
    if not m:
        m = re.search(r"""<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']+)""", landing)
    if m:
        live = m.group(1).strip().rstrip("/")

    repo_url = normalise_remote(git_remote(root))
    if not repo_url:
        m = re.search(r"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", landing + readme)
        if m:
            repo_url = m.group(0).rstrip(".")

    if not live and repo_url:
        live = derive_live(repo_url)

    local_landing = os.path.join(root, "docs", "index.html")
    local_app = os.path.join(root, "docs", "play", "index.html")
    return {
        "repo": root,
        "name": os.path.basename(root.rstrip(os.sep)),
        "repo_url": repo_url,
        "live": live,
        "readme": (repo_url + "#readme") if repo_url else "",
        "landing": (live + "/") if live else "",
        "app": (live + "/play/") if live else "",
        "support": (live + "/#support") if live else "",
        "local_landing": "file://" + urllib.parse.quote(local_landing) if os.path.exists(local_landing) else "",
        "local_app": "file://" + urllib.parse.quote(local_app) if os.path.exists(local_app) else "",
    }


def check(url):
    """HEAD the URL. Returns 'ok (200)', 'HTTP 404', or 'unreachable from here'.

    "unreachable from here" is not a verdict on the link: a sandbox with no
    egress, or a host outside its allowlist, says the same thing a dead URL
    does. Only an HTTP status is evidence.
    """
    if not url:
        return "no url"
    try:
        req = urllib.request.Request(url, method="HEAD",
                                     headers={"User-Agent": "estate-links/1.0"})
        with urllib.request.urlopen(req, timeout=8) as resp:
            return "ok (%d)" % resp.status
    except urllib.error.HTTPError as exc:
        return "HTTP %d" % exc.code
    except (urllib.error.URLError, OSError):
        return "unreachable from here"


def print_links(info, do_check=False, indent="  "):
    rows = [
        ("README", info["readme"]),
        ("landing page", info["landing"]),
        ("app demo", info["app"]),
        ("support block", info["support"]),
    ]
    width = max(len(label) for label, _ in rows)
    print("LINKS  %s" % info["name"])
    if not info["live"] and not info["repo_url"]:
        print("%sno live URL and no git remote — add <link rel=\"canonical\"> to docs/index.html,"
              " or set a remote" % indent)
        rows = []
    for label, url in rows:
        if not url:
            print("%s%-*s  (unknown — set og:url on the landing page, or a git remote)"
                  % (indent, width, label))
            continue
        suffix = ""
        if do_check:
            suffix = "  [%s]" % check(url)
        print("%s%-*s  %s%s" % (indent, width, label, url, suffix))
    for label, url in (("open locally", info["local_landing"]), ("app locally", info["local_app"])):
        if url:
            print("%s%-*s  %s" % (indent, width, label, url))
    if not info["live"] and info["repo_url"]:
        print("%snote: no live URL — add <link rel=\"canonical\"> to docs/index.html" % indent)


def main():
    ap = argparse.ArgumentParser(description="Print the README, landing page and app links for a repo.")
    ap.add_argument("repo", nargs="?", default=".", help="path to the repository")
    ap.add_argument("--check", action="store_true", help="ask each URL whether it answers")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    if not os.path.isdir(args.repo):
        sys.exit("not a directory: %s" % args.repo)

    info = links_for(args.repo)
    if args.json:
        if args.check:
            info["status"] = {k: check(info[k]) for k in ("readme", "landing", "app", "support")}
        print(json.dumps(info, indent=2))
        return 0

    print_links(info, args.check)
    return 0


if __name__ == "__main__":
    sys.exit(main())
