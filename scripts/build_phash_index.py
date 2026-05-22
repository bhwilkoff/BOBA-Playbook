#!/usr/bin/env python3
"""
Build the catalog pHash index for web Scan visual-similarity matching.

Each card with an `imageFile` gets a 64-bit perceptual hash (pHash)
computed from its R2 `thumbs/` image. The browser-side scanner computes
the same hash on the captured camera frame and Hamming-distance-matches
against this index.

Output: assets/data/phash-index.txt
Format: one line per card, `bobaId|<16-hex-char>`.

The hash format MUST stay in sync with `computeFramePhash` in js/app.js:
  - Resize image to 32x32
  - Convert to grayscale (luminance: 0.299R + 0.587G + 0.114B)
  - Run 2-D DCT-II
  - Take the top-left 8x8 block
  - Compute the median of [1..63] (drop DC at index 0)
  - bit i = (block[i] > median), packed LSB-first into a 64-bit BigInt

Hex encoding: 16 hex chars, big-endian (so `0x` + the string parses
into the same BigInt JavaScript computes).

Runtime: ~15-30 minutes for a full rebuild of 16K cards (concurrency-
limited HTTP fetches to R2). The default mode is INCREMENTAL — read
the existing phash-index.txt, skip cards already in it, only fetch
+ hash bobaIds not yet covered. A weekly rerun with no catalog growth
finishes in <10 seconds. Pass `--full` to force a complete rebuild.

CLI:
  python3 scripts/build_phash_index.py          # incremental (default)
  python3 scripts/build_phash_index.py --full   # full rebuild

Deps: pip install pillow requests
"""

from __future__ import annotations

import argparse

import json
import math
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from io import BytesIO
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow not installed. Run: pip install pillow requests", file=sys.stderr)
    sys.exit(1)

try:
    import requests
except ImportError:
    print("ERROR: requests not installed. Run: pip install pillow requests", file=sys.stderr)
    sys.exit(1)


CDN_BASE = "https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev"
THUMB_PREFIX = "thumbs/"
SEALED_THUMB_PREFIX = "sealed/thumbs/"

REPO_ROOT = Path(__file__).resolve().parent.parent
CARDS_JSON = REPO_ROOT / "assets" / "data" / "cards.json"
OUTPUT_FILE = REPO_ROOT / "assets" / "data" / "phash-index.txt"
WORKERS = 24       # concurrent HTTP fetches; R2 handles this easily
TIMEOUT_SEC = 20


def compute_phash(image_bytes: bytes) -> int:
    """Compute a 64-bit pHash matching the JS implementation."""
    img = Image.open(BytesIO(image_bytes)).convert("L")  # grayscale
    img = img.resize((32, 32), Image.Resampling.LANCZOS)
    pixels = list(img.getdata())  # 32*32 = 1024 floats

    # 2-D DCT-II via separable 1-D passes. Cosine matrix is the same
    # one JS uses; values match to within float precision.
    N = 32
    c0 = math.sqrt(1.0 / N)
    c1 = math.sqrt(2.0 / N)
    matrix = [
        [(c0 if k == 0 else c1) * math.cos((math.pi / N) * (n + 0.5) * k) for n in range(N)]
        for k in range(N)
    ]

    # Row pass
    temp = [0.0] * (N * N)
    for n in range(N):
        for k in range(N):
            s = 0.0
            for j in range(N):
                s += pixels[n * N + j] * matrix[k][j]
            temp[n * N + k] = s

    # Column pass
    out = [0.0] * (N * N)
    for l in range(N):
        for k in range(N):
            s = 0.0
            for n in range(N):
                s += temp[n * N + l] * matrix[k][n]
            out[k * N + l] = s

    # Take top-left 8x8 block; median of [1..63]; pack bits LSB-first.
    block = [out[y * N + x] for y in range(8) for x in range(8)]
    sorted_kept = sorted(block[1:])
    median = sorted_kept[len(sorted_kept) // 2]

    hash_val = 0
    for i in range(64):
        if block[i] > median:
            hash_val |= (1 << i)
    return hash_val


def fetch_and_hash(boba_id: str, image_file: str, is_sealed: bool) -> tuple[str, str | None]:
    """Fetch a card's thumbnail and return (bobaId, hex_hash_or_None)."""
    prefix = SEALED_THUMB_PREFIX if is_sealed else THUMB_PREFIX
    url = f"{CDN_BASE}/{prefix}{image_file}"
    try:
        r = requests.get(url, timeout=TIMEOUT_SEC)
        if r.status_code != 200:
            return (boba_id, None)
        h = compute_phash(r.content)
        # Big-endian hex so JavaScript's `BigInt('0x' + hex)` parses
        # to the same integer.
        return (boba_id, f"{h:016x}")
    except Exception as e:
        return (boba_id, None)


def load_existing_index() -> dict[str, str]:
    """Read the prior phash-index.txt into a {bobaId: hex_hash} dict.
    Returns empty when the file doesn't exist yet (first run)."""
    if not OUTPUT_FILE.exists():
        return {}
    out: dict[str, str] = {}
    for line in OUTPUT_FILE.read_text().splitlines():
        t = line.strip()
        if not t or t.startswith("#"):
            continue
        if "|" not in t:
            continue
        bid, _, h = t.partition("|")
        h = h.strip()
        if len(h) == 16:
            out[bid] = h
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--full",
        action="store_true",
        help="Force full rebuild — re-hash every card, ignoring the existing index. "
             "Default is incremental: only hash bobaIds not already in phash-index.txt.",
    )
    args = parser.parse_args()

    print(f"Loading {CARDS_JSON}...", flush=True)
    with open(CARDS_JSON) as f:
        cards = json.load(f)

    eligible_all = [
        (c["bobaId"], c["imageFile"], c.get("cardType") == "Sealed Product")
        for c in cards
        if c.get("bobaId") and c.get("imageFile")
    ]
    print(f"Cards with images: {len(eligible_all)} / {len(cards)}", flush=True)

    existing = {} if args.full else load_existing_index()
    if existing:
        print(f"Loaded existing index: {len(existing)} hashes (incremental mode)", flush=True)
    elif args.full:
        print("Full rebuild — ignoring any existing index", flush=True)

    eligible = [
        (bid, img, sealed)
        for (bid, img, sealed) in eligible_all
        if bid not in existing
    ]
    print(f"To hash this run: {len(eligible)}", flush=True)

    # Pre-seed results with the carried-over hashes so the final write
    # contains the complete set.
    results: dict[str, str] = dict(existing)
    skipped = 0
    started = time.time()

    new_hashed = 0
    if eligible:
        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            futures = {
                pool.submit(fetch_and_hash, bid, img, sealed): bid
                for bid, img, sealed in eligible
            }
            done = 0
            for fut in as_completed(futures):
                bid, h = fut.result()
                if h is not None:
                    results[bid] = h
                    new_hashed += 1
                else:
                    skipped += 1
                done += 1
                if done % 200 == 0:
                    rate = done / max(0.001, time.time() - started)
                    eta = (len(eligible) - done) / max(0.001, rate)
                    print(f"  {done}/{len(eligible)}  new={new_hashed}  skip={skipped}  rate={rate:.1f}/s  eta={eta/60:.1f}m", flush=True)

    elapsed = time.time() - started
    print(f"\nHashed {new_hashed} new cards in {elapsed/60:.1f} min  (skipped {skipped}, total in index: {len(results)})", flush=True)

    # Detect and report removed cards — bobaIds that USED to be in the
    # index but are no longer in cards.json. Pruning them keeps the
    # index clean as the catalog churns.
    catalog_ids = {bid for (bid, _, _) in eligible_all}
    pruned = [bid for bid in list(results.keys()) if bid not in catalog_ids]
    for bid in pruned:
        del results[bid]
    if pruned:
        print(f"Pruned {len(pruned)} hashes for bobaIds no longer in catalog", flush=True)

    # Short-circuit when nothing changed (incremental run with no new
    # cards + no pruning) — leave the existing file untouched so the
    # workflow's `git diff` reports no-op cleanly.
    if not args.full and new_hashed == 0 and not pruned:
        print("No new cards, no pruning — index unchanged. Exiting without rewriting file.", flush=True)
        return

    # Sort by bobaId for deterministic output (diff-friendly across reruns).
    lines = [f"{bid}|{results[bid]}" for bid in sorted(results.keys())]
    body = "\n".join(lines) + "\n"

    print(f"Writing {OUTPUT_FILE}...", flush=True)
    OUTPUT_FILE.write_text(
        f"# BOBA Playbook pHash index — generated by scripts/build_phash_index.py\n"
        f"# Cards: {len(results)} · Format: bobaId|<16-hex-char> (LSB-first 64-bit pHash)\n"
        f"# Browser-side hash MUST stay in sync with computeFramePhash in js/app.js.\n"
        + body
    )
    size_kb = OUTPUT_FILE.stat().st_size / 1024
    print(f"Wrote {OUTPUT_FILE.relative_to(REPO_ROOT)} ({size_kb:.0f} KB uncompressed).")


if __name__ == "__main__":
    main()
