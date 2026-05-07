#!/bin/sh
# Local helper — run before archiving from Mac Xcode to bump
# CURRENT_PROJECT_VERSION in AppVersion.xcconfig past the latest
# TestFlight build for the current marketing version.
#
# Pairs with ci_scripts/ci_post_clone.sh — both query the same ASC
# API endpoint, so Mac Xcode pushes and Xcode Cloud builds always
# converge on a strictly-increasing build number, never colliding.
#
# Usage:
#   export ASC_API_ISSUER_ID=<your-issuer-uuid>
#   ./scripts/bump-build.sh
#
# Then archive + upload as normal. The xcconfig bump is committed to
# git by you (the script doesn't auto-commit) so the next CI run also
# sees it. After a successful upload, optionally:
#   git commit AppVersion.xcconfig -m "Bump to v$X/$Y"
#
# To avoid putting the issuer ID on the command line every time,
# stash it in your shell profile or a .env.local file.

set -eu

cd "$(dirname "$0")/.."

if [ -z "${ASC_API_ISSUER_ID:-}" ]; then
    echo "bump-build: ASC_API_ISSUER_ID env var required."
    echo "  Get it from App Store Connect → Users and Access → Keys."
    exit 1
fi

KEY_ID="Y97R9U9WMG"
KEY_FILE="AuthKey_${KEY_ID}.p8"
BUNDLE_ID="app.bobaplaybook.ios"

if [ ! -f "$KEY_FILE" ]; then
    echo "bump-build: $KEY_FILE not found at repo root"
    exit 1
fi

MARKETING_VERSION=$(grep -E '^MARKETING_VERSION' AppVersion.xcconfig | awk '{print $3}')
CURRENT_BUILD=$(grep -E '^CURRENT_PROJECT_VERSION' AppVersion.xcconfig | awk '{print $3}')

JWT=$(python3 - <<EOF
import json, time, base64, os
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

key_id = "${KEY_ID}"
issuer = os.environ["ASC_API_ISSUER_ID"]
with open("${KEY_FILE}", "rb") as f:
    key = serialization.load_pem_private_key(f.read(), password=None)

header  = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
payload = {"iss": issuer, "iat": int(time.time()),
           "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"}

def b64(d):
    return base64.urlsafe_b64encode(json.dumps(d, separators=(',',':')).encode()).rstrip(b'=').decode()

signing_input = (b64(header) + "." + b64(payload)).encode()
sig_der = key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
r, s = decode_dss_signature(sig_der)
sig_raw = r.to_bytes(32, 'big') + s.to_bytes(32, 'big')
sig_b64 = base64.urlsafe_b64encode(sig_raw).rstrip(b'=').decode()
print(signing_input.decode() + "." + sig_b64)
EOF
)

APP_RESP=$(curl -fsS \
    -H "Authorization: Bearer $JWT" \
    "https://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=$BUNDLE_ID")
APP_ID=$(echo "$APP_RESP" | python3 -c 'import sys, json; print(json.load(sys.stdin)["data"][0]["id"])')

BUILDS_RESP=$(curl -fsS \
    -H "Authorization: Bearer $JWT" \
    "https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=$APP_ID&filter%5BpreReleaseVersion.version%5D=$MARKETING_VERSION&fields%5Bbuilds%5D=version&limit=200")

LATEST_BUILD=$(echo "$BUILDS_RESP" | python3 -c '
import sys, json
data = json.load(sys.stdin).get("data", [])
nums = [int(d["attributes"]["version"]) for d in data if d["attributes"]["version"].isdigit()]
print(max(nums) if nums else 0)
')

if [ "$LATEST_BUILD" -gt "$CURRENT_BUILD" ]; then
    NEXT_BUILD=$((LATEST_BUILD + 1))
else
    NEXT_BUILD=$((CURRENT_BUILD + 1))
fi

echo "bump-build: v${MARKETING_VERSION} latest TF build = ${LATEST_BUILD}, xcconfig was ${CURRENT_BUILD}"
echo "bump-build: writing CURRENT_PROJECT_VERSION = ${NEXT_BUILD}"

sed -i.bak -E "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $NEXT_BUILD/" AppVersion.xcconfig
rm -f AppVersion.xcconfig.bak

echo "bump-build: AppVersion.xcconfig now:"
grep -E '^(MARKETING_VERSION|CURRENT_PROJECT_VERSION)' AppVersion.xcconfig

echo ""
echo "Next: archive in Xcode (or commit + push to trigger Xcode Cloud)."
