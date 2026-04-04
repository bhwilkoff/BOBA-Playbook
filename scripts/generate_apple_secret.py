#!/usr/bin/env python3
"""
Generate an Apple client secret JWT for Supabase Sign in with Apple.

Usage:
    python3 scripts/generate_apple_secret.py

Prerequisites:
    pip3 install cryptography

The generated JWT is valid for 6 months (Apple's maximum).
Regenerate and update the Supabase Secret Key field before it expires.
"""

import json
import time
import base64
from pathlib import Path

# ── Configuration ─────────────────────────────────────────────────────────────
# Fill these in before running.

KEY_FILE  = "/Users/bhwilkoff/Documents/GitHub/BOBA-Playbook/AuthKey_Y97R9U9WMG.p8"
TEAM_ID   = "L2G756LY8N"
KEY_ID    = "Y97R9U9WMG"
CLIENT_ID = "app.bobaplaybook.ios.web"

# ── Script ────────────────────────────────────────────────────────────────────

def main():
    # Validate config
    missing = [name for name, val in [("KEY_FILE", KEY_FILE), ("TEAM_ID", TEAM_ID), ("KEY_ID", KEY_ID)] if not val]
    if missing:
        print(f"❌  Fill in these values at the top of the script before running: {', '.join(missing)}")
        return

    if not Path(KEY_FILE).exists():
        print(f"❌  .p8 file not found at: {KEY_FILE}")
        return

    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
    except ImportError:
        print("❌  Missing dependency. Run:  pip3 install cryptography")
        return

    def b64url(data):
        if isinstance(data, str):
            data = data.encode()
        return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

    with open(KEY_FILE, 'rb') as f:
        private_key = serialization.load_pem_private_key(f.read(), password=None)

    now     = int(time.time())
    expires = now + 15777000   # 6 months — Apple's maximum

    header  = b64url(json.dumps({"alg": "ES256", "kid": KEY_ID}, separators=(',', ':')))
    payload = b64url(json.dumps({
        "iss": TEAM_ID,
        "iat": now,
        "exp": expires,
        "aud": "https://appleid.apple.com",
        "sub": CLIENT_ID
    }, separators=(',', ':')))

    message = f"{header}.{payload}"
    sig_der = private_key.sign(message.encode(), ec.ECDSA(hashes.SHA256()))
    r, s    = decode_dss_signature(sig_der)
    raw_sig = b64url(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))

    jwt = f"{message}.{raw_sig}"

    from datetime import datetime
    exp_date = datetime.fromtimestamp(expires).strftime('%Y-%m-%d')

    print()
    print("✅  Apple client secret JWT (paste into Supabase → Auth → Providers → Apple → Secret Key):")
    print()
    print(jwt)
    print()
    print(f"⚠️   Expires: {exp_date} — set a calendar reminder to regenerate before then.")
    print()

if __name__ == "__main__":
    main()
