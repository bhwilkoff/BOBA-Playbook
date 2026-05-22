#!/usr/bin/env bash
# render.sh — render Play Console assets from HTML templates via headless
# Chrome. Outputs PNGs under tools/play-assets/out/. Re-run any time
# the templates change.
#
# Usage:
#   bash tools/play-assets/render.sh                # render everything
#   bash tools/play-assets/render.sh icon           # just the 512 icon
#   bash tools/play-assets/render.sh feature        # just the feature graphic
#
# For actual screenshots from the running app, use capture-screens.sh.
# HTML/CSS mockup screenshots are explicitly NOT shipped (per
# feedback_no_mockup_screenshots: "use real-app captures from a running
# emulator/device, NEVER ship HTML/CSS mockups dressed up as
# screenshots").

set -euo pipefail

cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT="$(pwd)/out"
TMPL="$(pwd)/templates"

mkdir -p "$OUT"

# Render one HTML file at a fixed window size to a PNG. Chrome's
# --screenshot output goes to ./screenshot.png by default; we redirect
# via a temp directory + rename so multiple invocations don't clobber.
render_one() {
  local html_file="$1"
  local out_name="$2"
  local width="$3"
  local height="$4"

  local tmpdir
  tmpdir="$(mktemp -d)"
  pushd "$tmpdir" >/dev/null

  "$CHROME" \
    --headless \
    --hide-scrollbars \
    --no-sandbox \
    --disable-gpu \
    --default-background-color=00000000 \
    --force-device-scale-factor=1 \
    --window-size="${width},${height}" \
    --screenshot="$tmpdir/out.png" \
    "file://$html_file" \
    >/dev/null 2>&1

  popd >/dev/null

  mv "$tmpdir/out.png" "$OUT/$out_name"
  rm -rf "$tmpdir"

  # Strip alpha channel for Play Console compatibility (Play rejects
  # the 512 icon when it carries an alpha channel — even all-opaque).
  # PIL composites onto the brand near-black so transparent regions
  # in the source get the same color as the canvas backgrounds in
  # the templates.
  python3 - "$OUT/$out_name" <<'PY'
from PIL import Image
import sys
path = sys.argv[1]
img = Image.open(path)
if img.mode == "RGBA":
    bg = Image.new("RGB", img.size, (8, 8, 16))  # var(--boba-near-black)
    bg.paste(img, mask=img.split()[3])
    bg.save(path, "PNG", optimize=True)
else:
    img.convert("RGB").save(path, "PNG", optimize=True)
PY

  printf "  ✓ %-32s %4dx%-4d  %s\n" \
    "$out_name" "$width" "$height" "$(du -h "$OUT/$out_name" | cut -f1)"
}

target="${1:-all}"

if [[ "$target" == "all" || "$target" == "icon" ]]; then
  echo "Rendering 512×512 app icon…"
  render_one "$TMPL/icon-512.html" "icon-512.png" 512 512
fi

if [[ "$target" == "all" || "$target" == "feature" ]]; then
  echo "Rendering 1024×500 feature graphic…"
  render_one "$TMPL/feature-graphic.html" "feature-graphic-1024x500.png" 1024 500
fi

if [[ "$target" == "screenshots" ]]; then
  echo "Mockup screenshots are disabled — use capture-screens.sh against a"
  echo "running emulator instead (per feedback_no_mockup_screenshots)."
  exit 1
fi

echo
echo "Output: $OUT"
ls -lh "$OUT" | tail -n +2
