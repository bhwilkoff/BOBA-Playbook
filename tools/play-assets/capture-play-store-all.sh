#!/usr/bin/env bash
# capture-play-store-all.sh
#
# Captures Play Store screenshots in 3 form factors using a single
# connected device: phone (native), 7" tablet (forced via `wm size`),
# 10" tablet (forced via `wm size`).
#
# WHY THIS WORKS: Android's window manager respects `wm size` +
# `wm density` overrides at the OS level. Compose's adaptive layout
# (NavigationSuiteScaffold + currentWindowAdaptiveInfo) responds to
# the size class derived from those values, switching from
# NavigationBar (compact) to NavigationRail (medium / expanded).
#
# At the end we ALWAYS reset wm back to "reset" so the user's
# device returns to normal. Don't ctrl-c this script mid-run.
#
# OUTPUT
#   tools/play-assets/out/play/<form>/screenshot-N-<name>.png
#   where <form> ∈ {phone, tablet-7, tablet-10}

set -euo pipefail

ADB=/opt/homebrew/bin/adb
PKG=com.bobaplaybook.app
ACTIVITY="$PKG/.MainActivity"

OUT_BASE="$(dirname "$0")/out/play"
mkdir -p "$OUT_BASE"

# ─── Original device state — restore on exit ─────────────────────
ORIG_SIZE="$($ADB shell wm size | grep -oE '[0-9]+x[0-9]+' | head -1)"
ORIG_DENSITY="$($ADB shell wm density | grep -oE '[0-9]+' | head -1)"
echo "Device baseline: ${ORIG_SIZE} @ ${ORIG_DENSITY}dpi"

cleanup() {
    echo
    echo "Restoring device size + density..."
    $ADB shell wm size reset
    $ADB shell wm density reset
    echo "Done."
}
trap cleanup EXIT

# ─── Helpers ─────────────────────────────────────────────────────
snap() {
    local form="$1"; local name="$2"
    mkdir -p "$OUT_BASE/$form"
    $ADB exec-out screencap -p > "$OUT_BASE/$form/$name"
    echo "    ✓ $form/$name  $(du -h "$OUT_BASE/$form/$name" | cut -f1)"
}

tap()  { $ADB shell input tap "$1" "$2"; sleep 1.5; }
launch() {
    $ADB shell am force-stop "$PKG" >/dev/null
    $ADB shell am start -n "$ACTIVITY" >/dev/null
    sleep 6.0  # Coil warmup for card-art grid
}

# Pre-capture device cleanup — kill any other foregrounded media /
# notifications / overlays that could bleed into the screenshot.
echo "Cleaning device before capture..."
# 1. Stop all media playback (video / music in OTHER apps).
$ADB shell input keyevent KEYCODE_MEDIA_STOP >/dev/null 2>&1 || true
$ADB shell input keyevent KEYCODE_MEDIA_PAUSE >/dev/null 2>&1 || true
# 2. Dismiss all notifications via Notification Manager service.
$ADB shell service call notification 1 >/dev/null 2>&1 || true
$ADB shell cmd notification clear_all >/dev/null 2>&1 || true
# 3. Go home + clear recents to make sure nothing is sitting on top.
$ADB shell input keyevent KEYCODE_HOME >/dev/null
sleep 1
# 4. Optional: pause Do Not Disturb so OS notifications don't pop in
#    mid-capture (best-effort; some OEM ROMs gate this differently).
$ADB shell cmd notification set_dnd priority >/dev/null 2>&1 || true

# Demo-mode status bar — clean clock 09:41, full bars, no notifications.
$ADB shell settings put global sysui_demo_allowed 1
demo() { $ADB shell am broadcast -a com.android.systemui.demo -e command "$@" >/dev/null; }
demo exit >/dev/null 2>&1 || true
demo enter
demo clock -e hhmm 0941
demo notifications -e visible false
demo network -e wifi show -e level 4
demo network -e mobile show -e level 4 -e datatype none
demo battery -e level 100 -e plugged false

# ─── Per-form-factor capture sequence ────────────────────────────
# Args: form_label  width  height  density  [nav_axis]  [coord_overrides...]
#   nav_axis = "bottom" (phone NavigationBar) or "left" (tablet NavigationRail)
capture_form() {
    local form="$1"; local w="$2"; local h="$3"; local density="$4"
    local nav_axis="$5"; shift 5
    local nav_coords=("$@")  # 5 "X,Y" pairs

    echo
    echo "════════════════════════════════════════════════════════"
    echo " $form  →  ${w}x${h} @ ${density}dpi  ($(($w*160/$density))dp wide, $nav_axis nav)"
    echo "════════════════════════════════════════════════════════"

    $ADB shell wm size "${w}x${h}"
    $ADB shell wm density "$density"
    sleep 2

    # 1. Find (default landing)
    launch
    sleep 4   # extra warmup for first image fetches
    snap "$form" "1-find.png"

    # 2-5: tap each remaining nav item
    local labels=(learn decks collection purchase)
    for i in 0 1 2 3; do
        IFS=',' read -r x y <<< "${nav_coords[$((i+1))]}"
        tap "$x" "$y"
        sleep 3
        snap "$form" "$((i+2))-${labels[$i]}.png"
    done
}

# ─── Phone: native 1080×2400 / 420dpi ────────────────────────────
# NavigationBar at bottom. 5 items across 1080px:
#   centers at x ≈ 108, 324, 540, 756, 972  (every 216px)
#   bottom-nav y ≈ 2280 (above 3-button / gesture pill)
PHONE_COORDS=(
    "540,1200"   # placeholder for Find (unused — landed by launch)
    "324,2280"   # Learn
    "540,2280"   # Decks
    "756,2280"   # Collection
    "972,2280"   # Purchase
)
capture_form phone 1080 2400 420 bottom "${PHONE_COORDS[@]}"

# ─── 7-inch tablet: 1200×1920 / 240dpi → 800dp wide → MEDIUM size class ───
# NavigationRail on LEFT. Actual tap targets verified via
# `uiautomator dump` (rail items are TEXT labels, tighter than I
# initially guessed). 90px spacing between item centers, first at y=169.
TABLET7_COORDS=(
    "59,169"    # Find  (snap before tapping — landed by launch)
    "59,259"    # Learn
    "59,349"    # Decks
    "60,439"    # Collection
    "60,529"    # Purchase
)
capture_form tablet-7 1200 1920 240 left "${TABLET7_COORDS[@]}"

# ─── 10-inch tablet: 1600×2560 / 240dpi → 1067dp wide → EXPANDED size class ───
# Rail same width / spacing in dp; first item shifted down ~32px by
# the larger top safe-area. Verified via uiautomator dump.
TABLET10_COORDS=(
    "59,201"    # Find
    "59,291"    # Learn
    "59,381"    # Decks
    "60,471"    # Collection
    "60,561"    # Purchase
)
capture_form tablet-10 1600 2560 240 left "${TABLET10_COORDS[@]}"

echo
echo "═══ Captured screenshots:"
find "$OUT_BASE" -name "*.png" | sort
