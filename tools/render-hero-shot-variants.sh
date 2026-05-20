#!/usr/bin/env bash
#
# render-hero-shot-variants.sh — headless 4-variant Hero Shot grid render.
#
# Spins up an iOS Simulator, installs the Debug app, launches it with
# BOBA_HERO_SHOT_CLI=1, polls for the grid PNG, and opens it. Designed
# to round-trip in <60s so you can iterate on Holofoil.metal / material
# variants without manual taps in HeroShotView.
#
# Usage:
#   tools/render-hero-shot-variants.sh                # default card / reveal arc
#   BOBA_HERO_SHOT_BOBA_ID="1-Maverick--" \
#     tools/render-hero-shot-variants.sh
#   BOBA_HERO_SHOT_ARC=showcase \
#     tools/render-hero-shot-variants.sh
#
# Output: /tmp/hero-shot-variants/grid.png
# Exit codes: 0=success, 1=build failed, 2=launch failed, 3=timeout
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${BOBA_HERO_SHOT_OUT_DIR:-/tmp/hero-shot-variants}"
DERIVED_DATA="${BOBA_HERO_SHOT_DD:-/tmp/hs-build}"
TIMEOUT_SEC="${BOBA_HERO_SHOT_TIMEOUT:-180}"

# Pick a simulator UDID. Prefer an already-booted device, otherwise
# pick the most-recent iPhone simulator.
DEVELOPER_DIR_RESOLVED=/Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR="$DEVELOPER_DIR_RESOLVED"

UDID="$(xcrun simctl list devices booted -j 2>/dev/null \
  | python3 -c "import sys,json;ds=[d for v in json.load(sys.stdin)['devices'].values() for d in v if d.get('state')=='Booted'];print(ds[0]['udid'] if ds else '')")"

if [[ -z "$UDID" ]]; then
  UDID="$(xcrun simctl list devices available -j \
    | python3 -c "import sys,json;ds=[d for k,v in json.load(sys.stdin)['devices'].items() if 'iOS' in k for d in v if d.get('isAvailable')];ds=[d for d in ds if 'iPhone' in d['name']];print(ds[-1]['udid'] if ds else '')")"
  if [[ -z "$UDID" ]]; then
    echo "ERROR: no iOS Simulator available — install one via Xcode → Settings → Components" >&2
    exit 2
  fi
  echo "[hs-cli] booting simulator $UDID"
  xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
fi
echo "[hs-cli] using simulator $UDID"

# Make sure the app is built.
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/BOBAPlaybook.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "[hs-cli] building app (no prior build found at $APP_PATH)…"
  xcodebuild -project BOBAPlaybook.xcodeproj \
    -scheme BOBAPlaybook \
    -destination "generic/platform=iOS Simulator" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    build >/tmp/hs-build.log 2>&1 \
    || { echo "ERROR: build failed — see /tmp/hs-build.log" >&2; exit 1; }
fi

# Reinstall + launch. simctl install replaces an existing bundle.
echo "[hs-cli] installing app"
xcrun simctl install "$UDID" "$APP_PATH"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"

# Resolve the app's host-side data container. After `install` the
# container exists even before first launch.
APP_DATA_DIR="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
HOST_OUT_DIR="$APP_DATA_DIR/Documents/hero-shot-variants"
rm -rf "$HOST_OUT_DIR"
mkdir -p "$HOST_OUT_DIR"
echo "[hs-cli] host-side output dir: $HOST_OUT_DIR"

# simctl forwards env vars prefixed with SIMCTL_CHILD_ to the launched
# process. That's the canonical way to pass --env-equivalent variables.
echo "[hs-cli] launching $BUNDLE_ID with BOBA_HERO_SHOT_CLI=1"
export SIMCTL_CHILD_BOBA_HERO_SHOT_CLI=1
[[ -n "${BOBA_HERO_SHOT_BOBA_ID:-}" ]] && export SIMCTL_CHILD_BOBA_HERO_SHOT_BOBA_ID="$BOBA_HERO_SHOT_BOBA_ID"
[[ -n "${BOBA_HERO_SHOT_ARC:-}" ]]     && export SIMCTL_CHILD_BOBA_HERO_SHOT_ARC="$BOBA_HERO_SHOT_ARC"

xcrun simctl launch \
  --terminate-running-process \
  "$UDID" "$BUNDLE_ID" >/dev/null

# Poll for the sentinel `done` file inside the app's Documents dir.
DEADLINE=$(( $(date +%s) + TIMEOUT_SEC ))
while [[ ! -f "$HOST_OUT_DIR/done" ]]; do
  if (( $(date +%s) > DEADLINE )); then
    echo "ERROR: timed out after ${TIMEOUT_SEC}s waiting for $HOST_OUT_DIR/done" >&2
    [[ -f "$HOST_OUT_DIR/error.txt" ]] && cat "$HOST_OUT_DIR/error.txt" >&2
    exit 3
  fi
  sleep 1
done

if [[ "$(cat "$HOST_OUT_DIR/done")" != "ok" ]]; then
  echo "ERROR: runner reported failure"
  [[ -f "$HOST_OUT_DIR/error.txt" ]] && cat "$HOST_OUT_DIR/error.txt" >&2
  exit 3
fi

GRID="$HOST_OUT_DIR/grid.png"
if [[ ! -f "$GRID" ]]; then
  echo "ERROR: $GRID missing despite ok sentinel" >&2
  exit 3
fi

# Mirror into /tmp for convenience so callers don't have to walk the
# simulator container path.
mkdir -p "$OUT_DIR"
cp "$GRID" "$OUT_DIR/grid.png"
cp "$HOST_OUT_DIR/done" "$OUT_DIR/done"

SIZE=$(stat -f%z "$GRID")
echo "[hs-cli] ✓ rendered $GRID ($SIZE bytes)"
echo "[hs-cli] ✓ mirrored to $OUT_DIR/grid.png"
echo "$OUT_DIR/grid.png"
