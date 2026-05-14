#!/bin/sh
# Xcode Cloud — runs after cloning the repo, before xcodebuild.
#
# Optional: queries App Store Connect API for the latest TestFlight
# build of this marketing version, then bumps CURRENT_PROJECT_VERSION
# to (latest_TF_build + 1). Lets Xcode Cloud and local Mac uploads
# share the same build-number source of truth so they don't collide
# on TestFlight.
#
# CRITICAL: every failure path below MUST exit 0 and let the build
# continue. Build-number sync is best-effort; without it, Xcode
# Cloud falls back to its own CI_BUILD_NUMBER which still produces
# valid (if non-synchronized) builds. This script must NEVER be a
# build blocker. v2.186 had `set -eu` plus `exit 1` branches that
# turned every misconfiguration into a build failure — fixed here.
#
# To actually enable the sync:
#   1. App Store Connect → Xcode Cloud → workflow → Environment →
#      Environment Variables: set ASC_API_ISSUER_ID to the team's
#      issuer UUID from Users and Access → Keys.
#   2. Same workflow → File Variables: upload AuthKey_<KEY_ID>.p8
#      with the literal filename so it materializes at the
#      workspace root during build. (The .p8 is gitignored — never
#      commit it.)

# Deliberately NOT using `set -eu`. Failures are handled explicitly
# below so an unexpected error somewhere never blocks the build.

cd "$CI_WORKSPACE" 2>/dev/null || {
    echo "ci_post_clone: cannot cd to CI_WORKSPACE — skipping, falling back to CI_BUILD_NUMBER"
    exit 0
}

if [ -z "${ASC_API_ISSUER_ID:-}" ]; then
    echo "ci_post_clone: ASC_API_ISSUER_ID unset — falling back to CI_BUILD_NUMBER"
    exit 0
fi

KEY_ID="Y97R9U9WMG"
KEY_FILE="AuthKey_${KEY_ID}.p8"
BUNDLE_ID="app.bobaplaybook.ios"

if [ ! -f "$KEY_FILE" ]; then
    echo "ci_post_clone: $KEY_FILE not found at workspace root (upload as Xcode Cloud File Variable to enable). Falling back to CI_BUILD_NUMBER."
    exit 0
fi

MARKETING_VERSION=$(grep -E '^MARKETING_VERSION' AppVersion.xcconfig 2>/dev/null | awk '{print $3}')
CURRENT_BUILD=$(grep -E '^CURRENT_PROJECT_VERSION' AppVersion.xcconfig 2>/dev/null | awk '{print $3}')

if [ -z "$MARKETING_VERSION" ] || [ -z "$CURRENT_BUILD" ]; then
    echo "ci_post_clone: AppVersion.xcconfig missing or unreadable — falling back to CI_BUILD_NUMBER"
    exit 0
fi

echo "ci_post_clone: bundle=$BUNDLE_ID  version=$MARKETING_VERSION  xcconfig-build=$CURRENT_BUILD"

# JWT generation. python3 + cryptography are pre-installed on
# Xcode Cloud runners but we still wrap in try/except so any
# unexpected import or key-format issue prints '' and we skip.
JWT=$(python3 - 2>/dev/null <<EOF
import json, time, base64, os, sys
try:
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
except Exception as e:
    print("", end="")
    sys.exit(0)
EOF
)

if [ -z "$JWT" ]; then
    echo "ci_post_clone: JWT generation failed — falling back to CI_BUILD_NUMBER"
    exit 0
fi

APP_RESP=$(curl -fsS \
    -H "Authorization: Bearer $JWT" \
    "https://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=$BUNDLE_ID" 2>/dev/null)
if [ -z "$APP_RESP" ]; then
    echo "ci_post_clone: ASC apps query failed — falling back to CI_BUILD_NUMBER"
    exit 0
fi

APP_ID=$(echo "$APP_RESP" | python3 -c 'import sys, json; d=json.load(sys.stdin).get("data",[]); print(d[0]["id"] if d else "")' 2>/dev/null)
if [ -z "$APP_ID" ]; then
    echo "ci_post_clone: could not parse APP_ID from ASC response — falling back to CI_BUILD_NUMBER"
    exit 0
fi

BUILDS_RESP=$(curl -fsS \
    -H "Authorization: Bearer $JWT" \
    "https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=$APP_ID&filter%5BpreReleaseVersion.version%5D=$MARKETING_VERSION&fields%5Bbuilds%5D=version&limit=200" 2>/dev/null)
if [ -z "$BUILDS_RESP" ]; then
    echo "ci_post_clone: ASC builds query failed — falling back to CI_BUILD_NUMBER"
    exit 0
fi

LATEST_BUILD=$(echo "$BUILDS_RESP" | python3 -c '
import sys, json
data = json.load(sys.stdin).get("data", [])
nums = [int(d["attributes"]["version"]) for d in data if d["attributes"]["version"].isdigit()]
print(max(nums) if nums else 0)
' 2>/dev/null)
if [ -z "$LATEST_BUILD" ]; then
    LATEST_BUILD=0
fi

if [ "$LATEST_BUILD" -gt "$CURRENT_BUILD" ] 2>/dev/null; then
    NEXT_BUILD=$((LATEST_BUILD + 1))
else
    NEXT_BUILD=$((CURRENT_BUILD + 1))
fi

echo "ci_post_clone: latest TF build for v${MARKETING_VERSION} = ${LATEST_BUILD}, bumping to ${NEXT_BUILD}"

sed -i.bak -E "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $NEXT_BUILD/" AppVersion.xcconfig 2>/dev/null
rm -f AppVersion.xcconfig.bak

echo "ci_post_clone: AppVersion.xcconfig now:"
grep -E '^(MARKETING_VERSION|CURRENT_PROJECT_VERSION)' AppVersion.xcconfig 2>/dev/null

exit 0
