#!/usr/bin/env bash
# capture-screens.sh — drive a running emulator through the 5 Play
# Store screens, take real screenshots via `adb shell screencap`.
# Assumes:
#   - Pixel 9 Pro AVD is booted (emulator-5554)
#   - The app is installed (com.bobaplaybook.app)
#   - Demo-mode status bar is configured (clock 09:41, full bars,
#     100% battery — see render.sh notes; or skip if you want real
#     status-bar content)
#
# Output: tools/play-assets/out/screenshot-N-<name>.png
#
# This script captures REAL app frames. The HTML mockups under
# templates/screenshot-*.html are kept around as fallback for when
# you want hand-designed marketing screenshots; the emulator path
# is the canonical Play Store screenshot source.

set -euo pipefail

ADB=/opt/homebrew/bin/adb
PKG=com.bobaplaybook.app
ACTIVITY="$PKG/.MainActivity"
OUT="$(dirname "$0")/out"
mkdir -p "$OUT"

# ─── Helpers ─────────────────────────────────────────────────────
dismiss_dialogs() {
  # Best-effort: if a system ANR / permission / wellbeing dialog is
  # in front of the app, the topResumedActivity will be something
  # other than com.bobaplaybook.app/.MainActivity. Press BACK up to
  # 3 times to clear; harmless if no dialog is showing (the app's
  # back behavior is gracefully no-op at root).
  for _ in 1 2 3; do
    local top
    top="$($ADB shell dumpsys activity activities 2>/dev/null \
            | grep 'topResumedActivity' | head -1 || true)"
    if [[ "$top" == *"com.bobaplaybook.app"* ]]; then return; fi
    $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
    sleep 1
  done
}

snap() {
  # Usage: snap <out-name>
  # screencap writes raw PNG to stdout; we redirect to a file on
  # the host. Faster + more reliable than the /sdcard intermediate
  # of older adb workflows. Always dismiss dialogs first so a
  # rogue Wellbeing / SystemUI ANR doesn't bleed into the frame.
  local name="$1"
  dismiss_dialogs
  $ADB exec-out screencap -p > "$OUT/$name"
  echo "  ✓ $name  $(du -h "$OUT/$name" | cut -f1)"
}
tap()      { $ADB shell input tap "$1" "$2"; sleep 1.0; }
back()     { $ADB shell input keyevent KEYCODE_BACK; sleep 1.0; }
home()     { $ADB shell input keyevent KEYCODE_HOME; sleep 0.5; }
swipe()    { $ADB shell input swipe "$@"; sleep 0.5; }
launch()   { $ADB shell am start -n "$ACTIVITY" >/dev/null; sleep 3.0; }

# ─── Demo-mode status bar (idempotent) ───────────────────────────
$ADB shell settings put global sysui_demo_allowed 1
demo() { $ADB shell am broadcast -a com.android.systemui.demo -e command "$@" >/dev/null; }
demo exit
demo enter
demo clock -e hhmm 0941
demo notifications -e visible false
demo network -e wifi show -e level 4
demo network -e mobile show -e level 4 -e datatype none
demo battery -e level 100 -e plugged false

# Pixel 9 Pro is 1280×2856 logical density. adb screencap returns
# the full framebuffer. Play Store accepts 1080-3840px on the short
# edge; we'll let it ride at native res and downscale if needed.

# ─── 1. Find ─────────────────────────────────────────────────────
# Force-stop + launch so we always land on the Find root tab.
$ADB shell am force-stop "$PKG"
launch
sleep 2
snap "screenshot-1-find.png"

# ─── 2. Card detail (tap the first card in the grid) ─────────────
# Card cells live in a LazyVerticalGrid; first cell on a 1280-wide
# Pixel 9 Pro lands around (240, 900). Tune if grid layout shifts.
tap 240 1000
sleep 2
snap "screenshot-2-card-detail.png"
back

# ─── NavigationBar (bottom of 2856px-tall screen) ────────────────
# 5 items spaced evenly across 1280px → centers at 128, 384, 640,
# 896, 1152. Pixel 9 Pro bottom-nav row y ≈ 2700 (above the gesture
# pill at ~2790).
NAV_Y=2700

# ─── 3. Decks (3rd of 5 nav items) ───────────────────────────────
tap 640 $NAV_Y
sleep 2
snap "screenshot-3-decks.png"

# ─── 4. Collection (4th of 5) ────────────────────────────────────
tap 896 $NAV_Y
sleep 2
snap "screenshot-4-collection.png"

# ─── 5. Learn → Tournament ───────────────────────────────────────
tap 384 $NAV_Y     # Learn (2nd of 5)
sleep 2
# Tournament category — 5th ListItem row in Learn root. ListItem
# rows are ~140dp tall (~ 224 px at density 480). With a TopAppBar
# offset of ~330 px, the 5th row centers around y = 330 + 4*224 + 112 = ~1338.
tap 640 1350
sleep 2
snap "screenshot-5-events.png"

echo
echo "Done. Output:"
ls -lh "$OUT"/screenshot-*.png
