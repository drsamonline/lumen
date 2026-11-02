#!/usr/bin/env python3
"""Check a repo's presentation surfaces, and fix the mechanical half.

    python3 scripts/verify.py /path/to/repo            # pass/fail report
    python3 scripts/verify.py /path/to/repo --audit    # the delta, and nothing else
    python3 scripts/verify.py /path/to/repo --fix      # generate the missing assets, then re-audit
    python3 scripts/verify.py /path/to/repo --json     # machine-readable

`--audit` is the one to run FIRST, before touching a repo: it lists only what is
missing or wrong, with the applicable fix for each, so a repo that is already
mostly right does not get rebuilt from scratch.

`--fix` writes only the two assets that carry no judgement — `upi-qr.svg` and
`support-portrait.jpg`. It will not touch HTML, the README, or the badges: a
badge's claim has to come from the repo's own suite, and a fix that invents
"567 passing" is the lie this whole skill exists to avoid.

After a `--fix` it prints the three links to check — the README, the landing
page, the app demo — because a repo is only done when someone can click through
it. `--check` also asks each URL whether it answers right now.

Exit status 1 if anything FAILs.
"""
import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

SUPPORT_HANDLES = [
    "drsohilboi@ybl",
    "ko-fi.com/matneo",
    "paypal.me/drsohilmomin",
    "B08ZT331LY",
    "drsamonline.github.io",
    "sohilmomin2000@gmail.com",
]
BADGES = ["live", "tests", "build", "licence", "offline", "deps"]
REMOTE_SRC = re.compile(r"""(?:src|href)\s*=\s*["'](?:https?:)?//""", re.I)
CSS_REMOTE = re.compile(r"url\(\s*['\"]?(?:https?:)?//", re.I)
CSS_VAR = re.compile(r"--([a-z0-9-]+)\s*:\s*(#[0-9a-fA-F]{3,8})")

# Build targets this estate does not ship: Windows, Linux and Android only.
MAC_TARGET = re.compile(
    r"(macos-latest|macos-1[0-9]|runs-on:\s*macos|\.dmg\b|\.pkg\b|\.ipa\b|testflight|"
    r"download for mac|mac app store|\bdarwin\b)", re.I)
IOS_WORD = re.compile(r"\bios\b|\biphone\b|\bipad\b", re.I)

# The surfaces the estate cares about, and the check that proves each one.
SURFACES = [
    ("landing", "docs/index.html exists"),
    ("app", "docs/play/index.html exists"),
    ("badges", "all six badge SVGs exist"),
    ("shots", "docs/assets/app-desktop.png looks like a real screenshot"),
    ("readme", "README has a Support section"),
    ("support", "landing page carries the support block"),
    ("portrait", "docs/assets/support-portrait.jpg exists"),
    ("theme", "the support block inherits the page palette"),
    ("offline", "no page loads anything from another origin"),
    ("platforms", "no macOS or iOS build targets"),
]


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def block_of(body, start=".support{", limit=4000):
    """The support block's own CSS, for the rules that apply only to it."""
    i = body.find(start)
    return body[i:i + limit] if i >= 0 else ""


# --- contrast ----------------------------------------------------------------
def _rgb(value):
    h = value.strip().lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _lum(rgb):
    def channel(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(fg, bg):
    a, b = _lum(_rgb(fg)), _lum(_rgb(bg))
    hi, lo = max(a, b), min(a, b)
    return round((hi + 0.05) / (lo + 0.05), 2)


def palettes(body):
    """Pull the two palettes out of a page, by the variable names this estate uses."""
    found = {}
    m = re.search(r":root\s*\{([^}]*)\}", body)
    if m:
        found["light"] = dict(CSS_VAR.findall(m.group(1)))
    m = re.search(r"""\[data-theme\s*=\s*["']?dark["']?\]\s*\{([^}]*)\}""", body)
    if m:
        found["dark"] = dict(CSS_VAR.findall(m.group(1)))
    if "dark" not in found:
        m = re.search(r"@media[^{]*prefers-color-scheme:\s*dark[^{]*\{\s*:root\s*\{([^}]*)\}", body)
        if m:
            found["dark"] = dict(CSS_VAR.findall(m.group(1)))
    return found


# --- the inspection ----------------------------------------------------------
def inspect(root):
    """Inspect a repo. Returns {repo, results, fails, warns}; results is a list of
    {status, label, detail, action}."""
    root = os.path.abspath(root)
    results = []

    def check(ok, label, detail="", action="", warn_only=False):
        results.append({
            "status": "warn" if (warn_only and not ok) else ("pass" if ok else "fail"),
            "label": label,
            "detail": detail,
            "action": action,
        })

    docs = os.path.join(root, "docs")
    assets = os.path.join(docs, "assets")
    landing = read(os.path.join(docs, "index.html"))
    app = read(os.path.join(docs, "play", "index.html"))
    readme = read(os.path.join(root, "README.md"))

    # --- structure -----------------------------------------------------------
    check(bool(landing), "docs/index.html exists",
          action="step 1-2: move the app to docs/play/ and build the landing page "
                  "from assets/landing-skeleton.html")
    check(bool(app), "docs/play/index.html exists",
          action="step 1: the app belongs at docs/play/index.html, with everything it loads")
    check("play/" in landing, "landing page points at the app at play/",
          "no href/src referencing play/",
          action="point the hero CTA and the demo frame at play/")
    check(bool(landing) and bool(app) and landing.strip() != app.strip(),
          "landing page is not a copy of the app",
          action="the landing page is its own design; keep the app in docs/play/ untouched")

    # --- platforms: Windows, Linux, Android. Nothing Apple. ------------------
    targets, ios_words = [], []
    scanned = [("README.md", readme),
               ("docs/index.html", landing),
               ("docs/play/index.html", app)]
    workflows = os.path.join(root, ".github", "workflows")
    if os.path.isdir(workflows):
        for name in sorted(os.listdir(workflows)):
            if name.endswith((".yml", ".yaml")):
                scanned.append((".github/workflows/" + name, read(os.path.join(workflows, name))))
    for rel, body in scanned:
        for m in MAC_TARGET.finditer(body):
            targets.append("%s: %s" % (rel, m.group(0)))
        for m in IOS_WORD.finditer(body):
            lead = body[max(0, m.start() - 16):m.start()].lower()
            if any(neg in lead for neg in ("no ", "not ", "never ", "without ")):
                continue  # "no macOS or iOS build" is the policy, not a violation
            ios_words.append("%s: %s" % (rel, m.group(0)))
    check(not targets, "no macOS or iOS build targets",
          "; ".join(sorted(set(targets))[:4]),
          action="this estate ships Windows, Linux and Android — delete the Apple target: the "
                 "macos runner, the .dmg/.pkg/.ipa, the App Store or TestFlight link, the "
                 "Download for Mac button")
    check(not ios_words, "no iOS wording on the pages",
          "; ".join(sorted(set(ios_words))[:4]), warn_only=True,
          action="check the wording: a device mock is fine, an iOS download is not")

    # --- the demo ------------------------------------------------------------
    check("<iframe" in landing, "landing page embeds the app in a frame",
          action="step 3: <iframe src=\"play/\"> behind a poster, revealed on load")
    check("poster" in landing, "the frame has a poster behind it", warn_only=True,
          action="keep the screenshot behind the frame so a blocked demo still shows the product")

    # --- themes --------------------------------------------------------------
    check("prefers-color-scheme" in landing, "landing page respects the system theme",
          action="light is the base palette; let prefers-color-scheme decide the first paint")
    check(re.search(r"localStorage\.(get|set)Item\(\s*['\"]theme:", landing) is not None,
          "landing page remembers its theme under its own key",
          action="store under a page-scoped key so the landing page and the app do not fight")
    check("data-theme" in landing, "landing page has a theme toggle", warn_only=True,
          action="add the header toggle, wired to the same variables")

    # --- contrast, computed rather than eyeballed ----------------------------
    found = palettes(landing)
    if "light" not in found:
        check(False, "the landing page's palette can be read",
              "no :root block with --ink/--paper variables", warn_only=True,
              action="name the palette variables --ink, --paper, --muted, --accent")
    for name, pal in found.items():
        ink, paper = pal.get("ink"), pal.get("paper")
        if not (ink and paper):
            check(False, "%s palette has ink and paper" % name, warn_only=True,
                  action="define --ink and --paper so the contrast can be computed")
            continue
        ratio = contrast(ink, paper)
        check(ratio >= 4.5, "%s theme: body text contrast %.2f:1" % (name, ratio),
              "WCAG AA for normal text is 4.5:1",
              action="darken --ink or lighten --paper in the %s palette" % name)
        muted = pal.get("muted")
        if muted:
            mratio = contrast(muted, paper)
            check(mratio >= 4.5, "%s theme: muted text contrast %.2f:1" % (name, mratio),
                  "secondary text is still text",
                  action="darken --muted in the %s palette" % name)
        accent = pal.get("accent")
        if accent:
            aratio = contrast(accent, paper)
            check(aratio >= 4.5, "%s theme: link contrast %.2f:1" % (name, aratio),
                  "AA wants 4.5:1 for link text", warn_only=True,
                  action="deepen --accent in the %s palette, or use it on a fill only" % name)
    if found and "dark" not in found:
        check(False, "the dark palette can be read", "no dark block found", warn_only=True,
              action="give the page a [data-theme=\"dark\"] block with the same variables")

    # --- badges and screenshots ---------------------------------------------
    present = [b for b in BADGES if os.path.exists(os.path.join(assets, "badge-%s.svg" % b))]
    check(len(present) == len(BADGES), "all six badge SVGs exist",
          "found %d/%d: %s" % (len(present), len(BADGES), ", ".join(present) or "none"),
          action="step 6: run scripts/badges.py with the repo's real claims")
    for b in present:
        try:
            ET.parse(os.path.join(assets, "badge-%s.svg" % b))
            ok, why = True, ""
        except ET.ParseError as exc:
            ok, why = False, str(exc)
        check(ok, "badge-%s.svg is valid SVG" % b, why,
              action="regenerate it: python3 scripts/badges.py")

    for name, floor in (("app-desktop.png", 8000), ("app-mobile.png", 4000)):
        p = os.path.join(assets, name)
        size = os.path.getsize(p) if os.path.exists(p) else 0
        check(size >= floor, "docs/assets/%s looks like a real screenshot" % name,
              "%d bytes" % size if size else "missing",
              action="step 5: scripts/shot.sh <repo> app app \"#/<populated route>\"")

    # --- README --------------------------------------------------------------
    check("<!-- shot:start -->" in readme and "<!-- shot:end -->" in readme,
          "README keeps the pipeline's shot markers",
          action="step 7: restore the shot:start/shot:end block — the pipeline writes into it")
    check(re.search(r"^##\s+Support\s*$", readme, re.M) is not None,
          "README has a Support section",
          action="add the Support table from assets/readme-template.md")
    check(not re.search(r"!\[[^\]]*\]\(\s*https?://", readme),
          "README images are local files, not an image service",
          action="commit the image and reference it by relative path")

    # --- a published page is not a draft ------------------------------------
    leftover = []
    for rel, body in (("docs/index.html", landing), ("README.md", readme)):
        for m in re.finditer(r"\{\{[^}\n]{1,80}\}\}", body):
            leftover.append("%s: %s" % (rel, m.group(0)))
    check(not leftover, "no unfilled {{placeholders}} left",
          "; ".join(sorted(set(leftover))[:4]),
          action="replace them: a published page still promising {{one-line promise}} is a draft "
                 "with a URL")

    check(not ("docs/shot.png" in readme and not os.path.exists(os.path.join(docs, "shot.png"))),
          "docs/shot.png exists where the README shows it", warn_only=True,
          action="the README's screenshot block points at a file that is not there — commit it, or "
                 "let the pipeline's shot job write it on the first build")

    # --- alt text, freshness, and the title a stranger sees -----------------
    no_alt = []
    for rel, body in (("docs/index.html", landing), ("docs/play/index.html", app)):
        for m in re.finditer(r"<img\b[^>]*>", body, re.I):
            tag = m.group(0)
            if "alt=" not in tag.lower():
                no_alt.append("%s: %s" % (rel, tag[:70]))
    check(not no_alt, "every <img> carries alt text",
          "; ".join(no_alt[:3]),
          action="write the alt text: what the picture shows, not 'image'")

    shot = os.path.join(assets, "app-desktop.png")
    if os.path.exists(shot):
        pages = [p for p in (os.path.join(docs, "index.html"),
                             os.path.join(docs, "play", "index.html")) if os.path.exists(p)]
        if pages:
            newest = max(os.path.getmtime(p) for p in pages)
            check(os.path.getmtime(shot) >= newest - 60,
                  "the screenshot is not older than the page",
                  "the page changed after the shot was taken", warn_only=True,
                  action="step 5: re-shoot — scripts/shot.sh <repo> landing && … app app")

    title = re.search(r"<title>(.*?)</title>", landing, re.S)
    if title:
        text = title.group(1).strip()
        check(10 <= len(text) <= 65, "the page title fits a search result",
              "%d characters" % len(text), warn_only=True,
              action="aim for under ~60 characters: the app name, then the promise")
    desc = re.search(r"""<meta[^>]+name=["']description["'][^>]+content=["']([^"']*)""", landing)
    if desc:
        check(len(desc.group(1)) <= 165, "the meta description fits a search result",
              "%d characters" % len(desc.group(1)), warn_only=True,
              action="trim it to under ~160 characters")

    # --- support block -------------------------------------------------------
    check("data-support" in landing, "landing page carries the support block",
          action="step 4: paste region 1 of assets/support-block.html into the footer")
    check("support-open" in app or "data-support" in app, "app carries the support button",
          warn_only=True, action="paste region 2 into the app header, region 1 inside its dialog")

    missing = [h for h in SUPPORT_HANDLES if h not in landing and h not in app]
    check(not missing, "all six support handles are present",
          "missing: %s" % ", ".join(missing) if missing else "",
          action="re-paste the block; never retype a handle")

    qr = os.path.join(assets, "upi-qr.svg")
    check(os.path.exists(qr) and os.path.getsize(qr) > 400 and "<svg" in read(qr),
          "docs/assets/upi-qr.svg exists and is an SVG",
          action="step 4: run scripts/support_qr.py (pip install segno)")
    check("upi://pay" in landing or "upi://pay" in app,
          "the UPI intent link is on the page",
          action="the VPA needs a upi://pay link as well as the printed text")
    check("am=" not in landing and "am=" not in app,
          "the UPI intent asks for an open amount",
          action="delete any am= parameter — no presets, no suggested tiers")

    portrait = os.path.join(assets, "support-portrait.jpg")
    psize = os.path.getsize(portrait) if os.path.exists(portrait) else 0
    check(psize > 4000, "docs/assets/support-portrait.jpg exists",
          "%d bytes" % psize if psize else "missing",
          action="step 4: run scripts/support_portrait.py --out docs/assets")
    check("support-portrait" in landing or "support-portrait" in app,
          "the portrait is in the support block",
          action="re-paste the block's region 1 — it carries the portrait markup")

    if "support-qr" in landing:
        check('src="assets/upi-qr.svg"' in landing,
              "landing page's QR path is assets/upi-qr.svg",
              action="fix the path; the landing page sits one level above assets/")
    if "support-qr" in app:
        check('src="../assets/upi-qr.svg"' in app,
              "the app's QR path is ../assets/upi-qr.svg",
              action="docs/play/ cannot reach assets/ without going up a level")
        check('src="../assets/support-portrait.jpg"' in app,
              "the app's portrait path is ../assets/support-portrait.jpg",
              action="same reason as the QR: up one level from docs/play/")

    # --- the block takes the host's theme, never its own ---------------------
    support_css = block_of(landing) + block_of(app)
    if support_css:
        check(support_css.count("var(--") >= 4,
              "the support block inherits the page palette",
              action="re-paste the block; it must read the host's variables, not carry a palette")
        dialog = block_of(landing, ".support-dialog{", 600) + block_of(app, ".support-dialog{", 600)
        bare = re.sub(r"var\([^)]*\)", "", dialog)  # a fallback inside var() is fine
        check(not re.search(r"#[0-9a-fA-F]{3,6}\b", bare),
              "the support dialog sets no colour of its own",
              action="delete the literal colour in .support-dialog — it takes the app's theme")
        check("prefers-color-scheme" not in support_css,
              "the support block adds no theme of its own",
              action="remove the media query from the block; the host page decides the theme")

    # --- offline honesty -----------------------------------------------------
    offenders = []
    for name, body in (("docs/index.html", landing), ("docs/play/index.html", app)):
        for m in REMOTE_SRC.finditer(body):
            frag = body[m.start():m.start() + 90].split(">")[0]
            if "noopener" in frag or "mailto:" in frag or "upi://" in frag:
                continue  # an outbound *link* is fine; a subresource is not
            if 'href="https' in frag or "href='https" in frag:
                continue
            offenders.append("%s: %s" % (name, frag.strip()[:80]))
        for m in CSS_REMOTE.finditer(body):
            offenders.append("%s: %s" % (name, body[m.start():m.start() + 60].split(")")[0]))
    check(not offenders, "no page loads anything from another origin",
          "; ".join(offenders[:3]),
          action="commit the asset locally and reference it by relative path")

    # --- service worker and installability ----------------------------------
    sw_path = os.path.join(docs, "play", "sw.js")
    if os.path.exists(sw_path):
        sw = read(sw_path)
        check(re.search(r"\bCACHE\b", sw) is not None, "sw.js declares a CACHE name",
              action="name the cache and bump it on every release")
        check("navigate" in sw, "sw.js serves HTML network-first (looks for 'navigate')",
              "a cache-first HTML handler hides every release",
              action="serve the HTML network-first; keep assets cache-first")
        check("serviceWorker" in app, "the app registers its service worker",
              warn_only=True, action="call navigator.serviceWorker.register('sw.js') on load")
    else:
        results.append({"status": "warn", "label": "no docs/play/sw.js",
                        "detail": "fine if the app has no service worker", "action": ""})

    manifest_path = None
    for candidate in ("docs/play/manifest.webmanifest", "docs/play/manifest.json",
                      "docs/manifest.webmanifest", "docs/manifest.json"):
        if os.path.exists(os.path.join(root, candidate)):
            manifest_path = os.path.join(root, candidate)
            break
    if manifest_path:
        raw = read(manifest_path)
        try:
            manifest = json.loads(raw)
            parsed, why = True, ""
        except ValueError as exc:
            manifest, parsed, why = {}, False, str(exc)
        check(parsed, "the manifest parses as JSON", why,
              action="fix the JSON; an unparseable manifest silently disables install")
        if parsed:
            icons = [i.get("sizes", "") for i in manifest.get("icons", []) if isinstance(i, dict)]
            flat = " ".join(icons).lower()
            gaps = []
            if not manifest.get("name") and not manifest.get("short_name"):
                gaps.append("no name")
            if "192" not in flat:
                gaps.append("no 192x192 icon")
            if "512" not in flat:
                gaps.append("no 512x512 icon")
            if manifest.get("display") not in ("standalone", "fullscreen", "minimal-ui"):
                gaps.append("display is %r" % manifest.get("display"))
            check(not gaps, "the manifest is installable", "; ".join(gaps), warn_only=True,
                  action="add the missing fields — name, 192 and 512 icons, display: standalone")
            check("play/" in raw or '"start_url": "./"' in raw,
                  "manifest start_url points at the app, not the landing page",
                  action="set start_url to the app's new path")
    else:
        results.append({"status": "warn", "label": "no web app manifest",
                        "detail": "fine if the app is not installable", "action": ""})

    check("theme-color" in landing, "the landing page declares a theme-color", warn_only=True,
          action="add <meta name=\"theme-color\"> for light and dark")

    check("stamp" in landing, "footer carries a build stamp", warn_only=True,
          action="print build date and commit in the footer so the release is answerable")

    fails = [r for r in results if r["status"] == "fail"]
    warns = [r for r in results if r["status"] == "warn"]
    return {"repo": root, "results": results, "fails": len(fails), "warns": len(warns)}


def surface_rows(report):
    """[(surface, status)] for the estate table — pass/warn/fail, or missing."""
    by_label = {r["label"]: r for r in report["results"]}
    rows = []
    for name, label in SURFACES:
        hit = by_label.get(label)
        rows.append((name, hit["status"] if hit else "missing"))
    return rows


# --- the mechanical fixes ----------------------------------------------------
def apply_fixes(root, report):
    """Generate the assets that carry no judgement. Returns the list of what it did."""
    root = os.path.abspath(root)
    assets = os.path.join(root, "docs", "assets")
    pending = {r["label"] for r in report["results"] if r["status"] != "pass"}
    did = []

    if "docs/assets/support-portrait.jpg exists" in pending:
        try:
            import support_portrait
            path, written = support_portrait.write_portrait(assets)
            did.append("%s %s" % ("wrote" if written else "already right:", os.path.relpath(path, root)))
        except Exception as exc:  # noqa: BLE001 - report, never crash the run
            did.append("portrait: skipped (%s)" % exc)

    if "docs/assets/upi-qr.svg exists and is an SVG" in pending:
        try:
            import support_qr
            path, uri = support_qr.write_qr(os.path.join(assets, "upi-qr.svg"))
            did.append("wrote %s" % os.path.relpath(path, root))
            did.append("  its intent is %s" % uri)
        except Exception as exc:  # noqa: BLE001
            did.append("upi-qr: skipped (%s)" % exc)

    if "all six badge SVGs exist" in pending:
        did.append("badges: not auto-generated — a claim has to come from the repo's own "
                   "suite. Run scripts/badges.py with the real numbers.")

    return did


def emit_links(root, do_check=False):
    """The clickable report: README, landing page, app demo."""
    try:
        import links as links_mod
    except ImportError:
        print("\nlinks: skipped — copy links.py next to verify.py to get the clickable report")
        return
    print()
    links_mod.print_links(links_mod.links_for(root), do_check)


def main():
    ap = argparse.ArgumentParser(description="Verify a repo's landing page, app, badges and support block.")
    ap.add_argument("repo", help="path to the repository")
    ap.add_argument("--audit", action="store_true",
                    help="report only the applicable changes, for a repo that already exists")
    ap.add_argument("--fix", action="store_true",
                    help="generate the missing QR and portrait, then re-audit")
    ap.add_argument("--links", action="store_true",
                    help="print the README, landing page and app links after the report")
    ap.add_argument("--check", action="store_true",
                    help="with --links/--fix, ask each URL whether it answers right now")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    if not os.path.isdir(args.repo):
        print("not a directory: %s" % args.repo, file=sys.stderr)
        return 2

    report = inspect(args.repo)

    if args.fix:
        done = apply_fixes(args.repo, report)
        print("FIX  %s" % report["repo"])
        for line in done or ["nothing to fix — the mechanical assets are already right"]:
            print("  · %s" % line)
        print()
        report = inspect(args.repo)

    fails, warns = report["fails"], report["warns"]
    todo = [r for r in report["results"] if r["status"] != "pass"]

    if (args.fix or args.links) and not args.json:
        emit_links(args.repo, args.check)
        if not args.audit:
            print()

    if args.json:
        print(json.dumps(report, indent=2))
        return 1 if fails else 0

    if args.audit:
        passing = len(report["results"]) - len(todo)
        print("AUDIT  %s" % report["repo"])
        print("  %d checks already pass — leave those surfaces alone." % passing)
        if not todo:
            print("  Nothing to apply. Do not rebuild this repo.")
            return 0
        print("  Apply only this, in order:\n")
        seen = []
        for r in todo:
            if not r["action"]:
                print("  · advisory: %s%s" % (r["label"],
                                              "  (%s)" % r["detail"] if r["detail"] else ""))
                continue
            if r["action"] in seen:
                continue
            seen.append(r["action"])
            print("  · %s" % r["action"])
            print("      because: %s%s" % (r["label"],
                                           "  (%s)" % r["detail"] if r["detail"] else ""))
        print("\n  %d to apply · %d failing · %d advisory" % (len(seen), fails, warns))
        return 1 if fails else 0

    mark = {"pass": "ok  ", "warn": "warn", "fail": "FAIL"}
    for r in report["results"]:
        line = "%s  %s" % (mark[r["status"]], r["label"])
        if r["detail"] and r["status"] != "pass":
            line += "  (%s)" % r["detail"]
        print(line)
        if r["status"] != "pass" and r["action"]:
            print("      -> %s" % r["action"])
    print("\n%d checks · %d failed · %d warnings" % (len(report["results"]), fails, warns))
    if fails:
        print("Fix the FAILs before reporting the repo as published.")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
