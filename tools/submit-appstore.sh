#!/usr/bin/env bash
# Build + upload App Store archives from the command line (no Xcode GUI). DEFAULT venue is the cloud
# workflow `.github/workflows/appstore-build.yml` (GitHub macos-26 runner = released macOS + Xcode 26.6),
# because the dev Mac is on a beta macOS and would be rejected ITMS-90301 locally. Signing is MANUAL via
# imported .p12s (cloud signing fails for this team key); on CI the cert id comes from ASC_DIST_CERT_ID.
# Adapted from Archive Watch's tools/submit-appstore.sh. Locally it only works on a RELEASED-macOS box.
#   tools/submit-appstore.sh <ios|tvos|all>
set -euo pipefail
cd "$(dirname "$0")/.."

# ===== per-app config (the ONLY per-repo difference) =====
PROJECT_FLAG=(-project "BOBAPlaybook.xcodeproj")
SCHEME="BOBAPlaybook"
XCCONFIG="AppVersion.xcconfig"                      # where MARKETING_VERSION / CURRENT_PROJECT_VERSION live
PLATFORMS="ios"
BID_FILTER="bobaplaybook"
TEAM="${ASC_TEAM_ID:-L2G756LY8N}"
# =========================================================

PLATFORM="${1:?usage: submit-appstore.sh <ios|tvos|all>}"
if [ "$PLATFORM" = "all" ]; then for p in $PLATFORMS; do "$0" "$p"; done; exit 0; fi
case "$PLATFORM" in
  ios)  DEST="generic/platform=iOS" ;;
  tvos) DEST="generic/platform=tvOS" ;;
  *) echo "unsupported platform '$PLATFORM' (use: $PLATFORMS all)"; exit 1 ;;
esac

# --- released Xcode (App Review rejects beta-Xcode builds) --------------------------------------
resolve_dev() {
  if [ -n "${DEVELOPER_DIR:-}" ]; then printf '%s\n' "$DEVELOPER_DIR"; return; fi
  local sel; sel="$(xcode-select -p 2>/dev/null)"
  case "$sel" in *[Bb]eta*) : ;; */Contents/Developer) printf '%s\n' "$sel"; return ;; esac
  local app
  for app in $(ls -d /Applications/Xcode*.app 2>/dev/null | grep -iv beta | sort -rV); do
    printf '%s\n' "$app/Contents/Developer"; return
  done
  printf '%s\n' "/Applications/Xcode.app/Contents/Developer"
}
DEV="$(resolve_dev)"; export DEVELOPER_DIR="$DEV"
case "$DEV" in *[Bb]eta*) echo "REFUSING beta Xcode ($DEV) — App Review rejects beta builds."; exit 1;; esac
[ -x "$DEV/usr/bin/xcodebuild" ] || { echo "No released Xcode at $DEV"; exit 1; }

# --- credentials (App Store Connect API key) ----------------------------------------------------
[ -f "tools/asc-credentials.env" ] && { set -a; . "tools/asc-credentials.env"; set +a; }
: "${ASC_KEY_ID:?set ASC_KEY_ID}"; : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
KEY="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
[ -f "$KEY" ] || { echo "Missing API key at $KEY"; exit 1; }
AUTH=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -authenticationKeyPath "$KEY")

# --- a Python that can import PyJWT (asc_certs/asc_profiles sign the ASC API JWT with it) --------
PY=python3
if ! python3 -c 'import jwt' 2>/dev/null; then
  VENV="tools/.asc-venv"
  if [ ! -x "$VENV/bin/python" ] || ! "$VENV/bin/python" -c 'import jwt' 2>/dev/null; then
    python3 -m venv "$VENV"; "$VENV/bin/pip" install -q --upgrade pip; "$VENV/bin/pip" install -q PyJWT cryptography
  fi
  PY="$VENV/bin/python"
fi

# Metal toolchain (only if a .metal shader is present; a no-op fast path otherwise).
"$DEV/usr/bin/xcrun" --find metal >/dev/null 2>&1 || { echo "Installing Metal toolchain…"; xcodebuild -downloadComponent MetalToolchain || true; }

VERSION="$(grep -E '^MARKETING_VERSION' "$XCCONFIG" | sed 's/.*= *//')"
BUILD="$(grep   -E '^CURRENT_PROJECT_VERSION' "$XCCONFIG" | sed 's/.*= *//')"
echo "[$PLATFORM] $SCHEME $VERSION ($BUILD) | $("$DEV/usr/bin/xcodebuild" -version | tr '\n' ' ') | $DEV"

ARCH="build/${PLATFORM}.xcarchive"; EXPORT="build/${PLATFORM}-export"
rm -rf "$ARCH" "$EXPORT"

echo "[$PLATFORM] archiving…"
xcodebuild "${PROJECT_FLAG[@]}" -scheme "$SCHEME" -configuration Release -destination "$DEST" \
  -archivePath "$ARCH" archive -allowProvisioningUpdates "${AUTH[@]}"

# --- embedded bundle ids (main app + extensions) ------------------------------------------------
APP="$(ls -d "$ARCH"/Products/Applications/*.app 2>/dev/null | head -1)"
[ -n "$APP" ] || { echo "no .app in $ARCH"; exit 1; }
BIDS=$(find "$APP" -name Info.plist 2>/dev/null | while read -r p; do
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$p" 2>/dev/null; done | grep "$BID_FILTER" | sort -u)
echo "[$PLATFORM] bundle ids: $(echo "$BIDS" | tr '\n' ' ')"

# --- Apple Distribution cert id (CI: ASC_DIST_CERT_ID from the imported .p12; local: find/create) -
if [ -n "${ASC_DIST_CERT_ID:-}" ]; then
  DIST_CERT_ID="$ASC_DIST_CERT_ID"; echo "[$PLATFORM] using CI signing cert $DIST_CERT_ID (imported .p12)"
else
  DIST_CERT_ID="$("$PY" tools/asc_certs.py distribution)"
  [ -n "$DIST_CERT_ID" ] || { echo "could not resolve/create Apple Distribution cert"; exit 1; }
fi

# --- App Store profiles per bundle id + a manual ExportOptions ----------------------------------
PJSON="$("$PY" tools/asc_profiles.py "$PLATFORM" "$DIST_CERT_ID" $BIDS)"
PLIST="$EXPORT-ExportOptions.plist"; mkdir -p "$(dirname "$PLIST")"
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  echo '<plist version="1.0"><dict>'
  echo '  <key>method</key><string>app-store-connect</string>'
  echo '  <key>destination</key><string>upload</string>'
  echo "  <key>teamID</key><string>$TEAM</string>"
  echo '  <key>signingStyle</key><string>manual</string>'
  echo "  <key>signingCertificate</key><string>Apple Distribution: Learning is Change, Inc. ($TEAM)</string>"
  echo '  <key>manageAppVersionAndBuildNumber</key><false/>'
  echo '  <key>provisioningProfiles</key><dict>'
  echo "$PJSON" | python3 -c "import json,sys
for k,v in json.load(sys.stdin).items(): print(f'    <key>{k}</key><string>{v}</string>')"
  echo '  </dict>'
  echo '</dict></plist>'
} > "$PLIST"

echo "[$PLATFORM] exporting + uploading to App Store Connect…"
xcodebuild -exportArchive -archivePath "$ARCH" -exportPath "$EXPORT" \
  -exportOptionsPlist "$PLIST" -allowProvisioningUpdates "${AUTH[@]}"

echo "✓ [$PLATFORM] uploaded $VERSION ($BUILD). In App Store Connect: select build $BUILD for the"
echo "  $PLATFORM platform → Submit for Review (processes for a few min)."
