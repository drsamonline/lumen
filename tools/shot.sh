#!/usr/bin/env bash
# Screenshot a repo's landing page and app with headless Chromium.
#
#   scripts/shot.sh /path/to/repo                      # landing page -> landing-desktop/mobile.png
#   scripts/shot.sh /path/to/repo app                  # the app      -> app-desktop/mobile.png
#   scripts/shot.sh /path/to/repo app app "#/remedy/x" # the app on a populated route
#   scripts/shot.sh /path/to/repo landing hero 1900    # taller desktop canvas
#
# Writes a desktop (1280 wide) and a phone (430 wide) shot into docs/assets/.
# Look at them before committing: a page that renders wrong is worse than none.
#
# SCALE=2 gives a retina shot at double the bytes — handy for og:image, but a
# 600 KB PNG will 413 a multi-file commit, so add those files one at a time.
set -euo pipefail

REPO="${1:?usage: shot.sh <repo-path> [landing|app] [out-name] [route] [desktop-height]}"
KIND="${2:-landing}"
NAME="${3:-$KIND}"
ROUTE="${4:-}"
HEIGHT="${5:-1600}"
ROOT="$(cd "$REPO" && pwd)"

if [ "$KIND" = "app" ]; then PAGE="$ROOT/docs/play/index.html"; else PAGE="$ROOT/docs/index.html"; fi
[ -f "$PAGE" ] || { echo "no page at $PAGE"; exit 1; }

mkdir -p "$ROOT/docs/assets"
CHROME="$(command -v chromium || command -v chromium-browser || command -v google-chrome || true)"
[ -n "$CHROME" ] || { echo "no chromium on PATH"; exit 1; }

URL="file://$PAGE$ROUTE"
SCALE="${SCALE:-1}"

shoot () { # width, height, outfile
  local out="$3"
  rm -f "$out"
  # --headless=new is the only form newer Chromium accepts; older builds reject it.
  for mode in "--headless=new" "--headless"; do
    "$CHROME" $mode --no-sandbox --disable-gpu --hide-scrollbars \
      --force-device-scale-factor="$SCALE" \
      --virtual-time-budget=6000 --run-all-compositor-stages-before-draw \
      --window-size="$1,$2" --screenshot="$out" "$URL" >/dev/null 2>&1 || true
    [ -s "$out" ] && break
  done
  if [ ! -s "$out" ]; then echo "FAILED to shoot $URL at $1x$2"; return 1; fi
  echo "wrote $out ($(stat -c%s "$out") bytes, ${1}x${2} @${SCALE}x)"
}

shoot 1280 "$HEIGHT" "$ROOT/docs/assets/${NAME}-desktop.png"
shoot 430  860      "$ROOT/docs/assets/${NAME}-mobile.png"

echo
echo "Now open both files and look at them. Then check the other theme:"
echo "  $CHROME --headless=new --no-sandbox --window-size=1280,900 --screenshot=/tmp/light.png \"$URL\""
