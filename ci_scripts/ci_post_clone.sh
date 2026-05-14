#!/bin/sh
# Xcode Cloud — runs after cloning the repo, before xcodebuild.
#
# Sets CURRENT_PROJECT_VERSION in AppVersion.xcconfig to (latest
# TestFlight build for this marketing version) + 1, queried from
# the App Store Connect API. This makes Xcode Cloud and local Mac
# Xcode pushes both bump from the same source of truth (ASC) so
# the two upload paths never collide.
#
# Without this, Xcode Cloud uses CI_BUILD_NUMBER (the count of CI
# runs ≈ 214) while Mac Xcode reads the xcconfig (≈ 367) — two
# independent counters that can collide on TestFlight uploads.
#
# Required Xcode Cloud env vars (set in App Store Connect →
# Xcode Cloud → workflow → Environment → Environment Variables):
#   ASC_API_ISSUER_ID  — your team's issuer UUID from
#                        ASC → Users and Access → Keys
#
# Required repo file:
#   AuthKey_Y97R9U9WMG.p8  — already at repo root; key ID baked in
#                            below.
#
# This script is a NO-OP (with a log line) when ASC_API_ISSUER_ID
# is unset, so the workflow still runs even before secrets are
# configured.

set -eu

cd "$CI_WORKSPACE"

if [ -z "${ASC_API_ISSUER_ID:-}" ]; then
    echo "ci_post_clone: ASC_API_ISSUER_ID unset — falling back to xcconfig value (no ASC query)"
    grep -E '^(MARKETING_VERSION|CURRENT_PROJECT_VERSION)' AppVersion.xcconfig
    exit 0
fi

KEY_ID="Y97R9U9WMG"
KEY_FILE="AuthKey_${KEY_ID}.p8"
BUNDLE_ID="app.bobaplaybook.ios"

if [ ! -f "$KEY_FILE" ]; then
    echo "ci_post_clone: $KEY_FILE not found at workspace root — skipping ASC sync."
    echo "  *.p8 is gitignored (correctly — private key). To enable ASC sync on"
    echo "  Xcode Cloud, upload the key as a workflow File Variable in App Store"
    echo "  Connect → Xcode Cloud → workflow → Environment → File Variables, named"
    echo "  $KEY_FILE so it materializes at the workspace root during build."
    echo "  Falling back to xcconfig CURRENT_PROJECT_VERSION + CI_BUILD_NUMBER."
    grep -E '^(MARKETING_VERSION|CURRENT_PROJECT_VERSION)' AppVersion.xcconfig
    exit 0
fi

MARKETING_VERSION=$(grep -E '^MARKETING_VERSION' AppVersion.xcconfig | awk '{print $3}')
CURRENT_BUILD=$(grep -E '^CURRENT_PROJECT_VERSION' AppVersion.xcconfig | awk '{print $3}')

echo "ci_post_clone: bundle=$BUNDLE_ID  version=$MARKETING_VERSION  xcconfig-build=$CURRENT_BUILD"

# Build a JWT for ASC API auth using Python (Xcode Cloud runners
# have python3 + cryptography pre-installed). Output: a bearer token
# valid for 20 minutes.
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

# Look up the app's ASC ID from the bundle ID.
APP_RESP=$(curl -fsS \
    -H "Authorization: Bearer $JWT" \
    "https://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=$BUNDLE_ID")
APP_ID=$(echo "$APP_RESP" | python3 -c 'import sys, json; print(json.load(sys.stdin)["data"][0]["id"])')

# Fetch the highest build number across ALL TestFlight builds of
# this marketing version. Page size 200 covers our usage; widen if
# we ever cross that.
BUILDS_RESP=$(curl -fsS \
    -H "Authorization: Bearer $JWT" \
    "https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=$APP_ID&filter%5BpreReleaseVersion.version%5D=$MARKETING_VERSION&fields%5Bbuilds%5D=version&limit=200")

LATEST_BUILD=$(echo "$BUILDS_RESP" | python3 -c '
import sys, json
data = json.load(sys.stdin).get("data", [])
nums = [int(d["attributes"]["version"]) for d in data if d["attributes"]["version"].isdigit()]
print(max(nums) if nums else 0)
')

# Take the larger of (latest TF build, current xcconfig value), then
# add 1. The xcconfig floor handles the cold-start case where ASC
# returns 0 (no prior build for this version).
if [ "$LATEST_BUILD" -gt "$CURRENT_BUILD" ]; then
    NEXT_BUILD=$((LATEST_BUILD + 1))
else
    NEXT_BUILD=$((CURRENT_BUILD + 1))
fi

echo "ci_post_clone: latest TF build for v${MARKETING_VERSION} = ${LATEST_BUILD}, bumping to ${NEXT_BUILD}"

# Rewrite the xcconfig in-place (CI workspace only; no commit).
sed -i.bak -E "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $NEXT_BUILD/" AppVersion.xcconfig
rm -f AppVersion.xcconfig.bak

echo "ci_post_clone: AppVersion.xcconfig now:"
grep -E '^(MARKETING_VERSION|CURRENT_PROJECT_VERSION)' AppVersion.xcconfig
