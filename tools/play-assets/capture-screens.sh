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
# This script captures REAL app frames — the canonical Play Store
# screenshot source. HTML/CSS mockup screenshots are explicitly out
# of scope (per feedback_no_mockup_screenshots); the templates were
# deleted at tick 205. Boot the Pixel 9 Pro AVD from Android Studio's
# Device Manager before running (CLI cold-boot is unreliable).

set -euo pipefail

ADB=/opt/homebrew/bin/adb
PKG=com.bobaplaybook.app
ACTIVITY="$PKG/.MainActivity"
OUT="$(dirname "$0")/out"
mkdir -p "$OUT"

# ─── Helpers ─────────────────────────────────────────────────────
dismiss_dialogs() {
  # Best-effort: if a system ANR / permission / wellbeing dialog is
  # in front of the app, the topResumedActivity will be a DIALOG
  # activity sitting above us. Press BACK up to 3 times to clear.
  #
  # PRE-2026-05-22 BUG: the prior version pressed BACK whenever
  # topResumedActivity wasn't BOBA — including when the launcher
  # was still briefly on top during an `am start` transition, OR
  # when dumpsys returned empty mid-launch (BACK on an empty
  # string is just home, which the launcher catches → we land on
  # the home screen instead of in the app). Now we only BACK when
  # we positively identify a NON-launcher NON-BOBA activity on
  # top, which is the only situation BACK should be used.
  for _ in 1 2 3; do
    local top
    top="$($ADB shell dumpsys activity activities 2>/dev/null \
            | grep 'topResumedActivity' | head -1 || true)"
    # Empty → still launching, don't touch
    [[ -z "$top" ]] && { sleep 1; continue; }
    # BOBA is on top → done
    [[ "$top" == *"com.bobaplaybook.app"* ]] && return
    # Launcher is on top → app hasn't fully started yet, don't BACK
    # (that would take us deeper into the launcher / home screen)
    [[ "$top" == *"NexusLauncherActivity"* || "$top" == *"Launcher"* ]] && { sleep 1; continue; }
    # Something else (genuine dialog) — dismiss it
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
tap()      { $ADB shell input tap "$1" "$2"; sleep 1.5; }
back()     { $ADB shell input keyevent KEYCODE_BACK; sleep 1.5; }
home()     { $ADB shell input keyevent KEYCODE_HOME; sleep 0.5; }
swipe()    { $ADB shell input swipe "$@"; sleep 0.5; }
# Bumped post-launch sleep 3s → 6s. The card-art grid is populated
# by Coil on a background thread after cards.json decode; without
# this extra wait the Find capture lands on an empty-cell grid.
launch()   { $ADB shell am start -n "$ACTIVITY" >/dev/null; sleep 6.0; }

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
# launch() includes a 6s settle for Coil to populate the grid art.
$ADB shell am force-stop "$PKG"
launch
sleep 4    # extra warmup for the first image fetches
snap "screenshot-1-find.png"

# ─── 2. Card detail (tap the first card in the grid) ─────────────
# Card cells live in a LazyVerticalGrid; first cell on a 1280-wide
# Pixel 9 Pro lands around (240, 900). Tune if grid layout shifts.
tap 240 1000
sleep 4    # CardDetailScreen artPanel needs time to render
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
sleep 3
# Learn root is a 2-column grid of 6 category cards (Rules /
# Strategy / Collect / Watch / Glossary / Tournament). Tournament
# is the bottom-right cell. The grid fills the top ~64% of the
# 1280×2856 canvas (header + empty bottom space below):
#   col-left  center ≈ 320  ·  col-right center ≈ 940
#   row-1 (Rules / Strategy)        center ≈  770
#   row-2 (Collect / Watch)         center ≈ 1185
#   row-3 (Glossary / Tournament)   center ≈ 1620
# Tournament is row-3 col-right ≈ (940, 1620).
tap 940 1620
sleep 4
snap "screenshot-5-tournament.png"

echo
echo "Done. Output:"
ls -lh "$OUT"/screenshot-*.png
