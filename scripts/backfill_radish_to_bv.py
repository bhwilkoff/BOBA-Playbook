#!/usr/bin/env python3
"""
backfill_radish_to_bv.py — replace Radish-sourced card images with
the card source-sourced images for cards whose `imageSource == "RADISH"`.

Why this exists: per DECISIONS.md #056 + RADISH_REMOVAL_LOOP.md, the
8,386 cards whose canonical image was originally pulled from Radish
need to flip to a non-Radish provenance. The R2 bytes can stay (they're
our property per DECISIONS.md #008) but going forward we want
`imageSource: "BV"` on cards where BV has a real alternative — the
backfill walks the existing BV CSV scan results and replaces the bytes
at the same R2 path so app URLs stay unchanged.

Pipeline contract:
  reads   assets/data/radish_backfill_queue.json   (Phase 9 helper output)
          pipeline/data/scan_results.csv         (BV CSV catalog)
  writes  R2: full/{imageFile} + thumbs/{imageFile}  (overwrites existing)
          assets/data/cards.json                     (imageSource → "BV")
          + 5 downstream bundle JSONs (display-cards, cards-head, etc.)

Each successful card:
  - downloads BV image bytes (public CDN, no auth)
  - resizes to ≤1200px long-side as webp quality=85 → R2 full/
  - resizes to 200px long-side as webp quality=80 → R2 thumbs/
  - flips imageSource: "RADISH" → "BV" in every catalog JSON
  - leaves `radishUrl` UNCHANGED (per Option B in RADISH_REMOVAL_LOOP.md
    — the per-card "View on Radish" link still uses it)

Usage:
  python3 scripts/backfill_radish_to_bv.py --limit 20    # dry-run subset
  python3 scripts/backfill_radish_to_bv.py               # full run

Env: R2_ACCOUNT_ID, R2_ACCESS_KEY, R2_SECRET_KEY, R2_BUCKET (from .env)

Idempotent: re-running skips cards whose `imageSource` is already non-RADISH.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import os
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Optional

import boto3
import requests
from botocore.config import Config
from dotenv import load_dotenv
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(REPO_ROOT / ".env")

USER_AGENT = "Mozilla/5.0 (compatible; BoBA-RadishBackfill/1.0)"
BV_CSV_PATH = REPO_ROOT / "pipeline" / "data" / "scan_results.csv"
DEFAULT_QUEUE = REPO_ROOT / "assets" / "data" / "radish_backfill_queue.json"

# Every catalog JSON file that mirrors the master cards.json. Each card
# row is keyed by bobaId; we update imageSource in lockstep across all.
CATALOG_FILES = [
    REPO_ROOT / "assets" / "data" / "cards.json",
    REPO_ROOT / "assets" / "data" / "display-cards.json",
    REPO_ROOT / "assets" / "data" / "cards-head.json",
    REPO_ROOT / "assets" / "data" / "cards-slim.json",
    REPO_ROOT / "BOBAPlaybook" / "display-cards.json",
    REPO_ROOT / "BOBAPlaybook" / "cards-head.json",
    REPO_ROOT / "android" / "app" / "src" / "main" / "assets" / "data" / "cards.json",
    REPO_ROOT / "android" / "app" / "src" / "main" / "assets" / "data" / "cards-head.json",
]


def make_r2_client():
    return boto3.client(
        "s3",
        endpoint_url=f"https://{os.environ['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",
        aws_access_key_id=os.environ["R2_ACCESS_KEY"],
        aws_secret_access_key=os.environ["R2_SECRET_KEY"],
        config=Config(signature_version="s3v4", retries={"max_attempts": 3}),
    )


def normalize_name(s: str) -> str:
    return "".join(ch for ch in (s or "").lower() if ch.isalnum())


def index_bv_csv() -> dict[str, list[dict]]:
    """Index BV rows by external_card_number → list of candidate rows."""
    if not BV_CSV_PATH.exists():
        raise FileNotFoundError(f"BV CSV missing at {BV_CSV_PATH}")
    out: dict[str, list[dict]] = {}
    with BV_CSV_PATH.open() as f:
        for row in csv.DictReader(f):
            if row.get("is_placeholder") != "0":
                continue
            if not row.get("image_url"):
                continue
            cn = (row.get("external_card_number") or "").strip()
            if not cn:
                continue
            out.setdefault(cn, []).append(row)
    return out


def match_bv_row(card: dict, candidates: list[dict]) -> Optional[dict]:
    """Pick the BV row whose name best matches the catalog card's hero/name."""
    target = normalize_name(card.get("hero") or card.get("name") or "")
    if not target:
        return candidates[0] if candidates else None
    best, best_score = None, 0
    for r in candidates:
        nn = normalize_name(r.get("name") or "")
        if not nn:
            continue
        if target == nn:
            score = 3
        elif nn.startswith(target) or target.startswith(nn):
            score = 2
        elif target in nn or nn in target:
            score = 1
        else:
            continue
        if score > best_score:
            best_score, best = score, r
    return best


def download_bv_image(url: str) -> Optional[bytes]:
    try:
        resp = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=20)
        resp.raise_for_status()
        return resp.content
    except Exception as e:
        print(f"    download failed: {e}", file=sys.stderr)
        return None


def to_webp(image_bytes: bytes, max_long_side: int, quality: int) -> bytes:
    img = Image.open(io.BytesIO(image_bytes))
    if img.mode != "RGB":
        img = img.convert("RGB")
    w, h = img.size
    long_side = max(w, h)
    if long_side > max_long_side:
        scale = max_long_side / long_side
        new_size = (int(w * scale), int(h * scale))
        img = img.resize(new_size, Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="WEBP", quality=quality, method=6)
    return buf.getvalue()


def upload_to_r2(r2, bucket: str, key: str, body: bytes, content_type: str = "image/webp") -> bool:
    try:
        r2.put_object(Bucket=bucket, Key=key, Body=body, ContentType=content_type,
                      CacheControl="public, max-age=604800")
        return True
    except Exception as e:
        print(f"    R2 upload failed: {e}", file=sys.stderr)
        return False


def update_catalogs(updated_boba_ids: set[str], from_source: str = "RADISH", new_source: str = "BV") -> dict[str, int]:
    """Flip imageSource on every catalog file in lockstep. Returns
    per-file count of rows updated. Only flips rows whose current
    imageSource matches `from_source` — protects against accidentally
    rewriting non-RADISH cards if a queue is misconfigured."""
    counts = {}
    for path in CATALOG_FILES:
        if not path.exists():
            counts[str(path.relative_to(REPO_ROOT))] = -1
            continue
        cards = json.loads(path.read_text())
        n = 0
        for c in cards:
            bid = c.get("bobaId")
            if bid in updated_boba_ids and c.get("imageSource") == from_source:
                c["imageSource"] = new_source
                n += 1
        path.write_text(json.dumps(cards, indent=2))
        counts[str(path.relative_to(REPO_ROOT))] = n
    return counts


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--limit", type=int, default=0,
                    help="Process at most N cards (0 = no limit)")
    ap.add_argument("--dry-run", action="store_true",
                    help="Skip downloads, R2 uploads, and catalog edits")
    ap.add_argument("--start", type=int, default=0,
                    help="Skip the first N cards in the queue (for resume)")
    ap.add_argument("--workers", type=int, default=10,
                    help="Concurrent download/upload workers (default 10)")
    ap.add_argument("--queue", default=str(DEFAULT_QUEUE),
                    help="Backfill queue JSON to read (default: assets/data/radish_backfill_queue.json)")
    ap.add_argument("--from-source", default="RADISH",
                    help="Catalog imageSource value to replace (default: RADISH)")
    ap.add_argument("--new-source", default="BV",
                    help="New imageSource value to write (default: BV)")
    args = ap.parse_args()

    queue_path = Path(args.queue)
    if not queue_path.is_absolute():
        queue_path = REPO_ROOT / args.queue

    if not queue_path.exists():
        print(f"Queue not found at {queue_path} — run scripts/identify_radish_sourced_cards.py first.", file=sys.stderr)
        return 1
    queue = json.loads(queue_path.read_text())
    bv_index = index_bv_csv()
    bucket = os.environ.get("R2_BUCKET", "boba-card-images")
    r2 = make_r2_client() if not args.dry_run else None

    counters = {"matched": 0, "no_bv_row": 0, "download_err": 0, "upload_err": 0}
    counters_lock = threading.Lock()
    succeeded_boba_ids: set[str] = set()
    succeeded_lock = threading.Lock()
    started_at = time.time()

    slice_end = args.start + args.limit if args.limit > 0 else len(queue)
    work = queue[args.start:slice_end]
    print(f"Backfill: processing {len(work):,} of {len(queue):,} queued cards "
          f"(start={args.start}, limit={args.limit}, workers={args.workers}, dry_run={args.dry_run})")

    def process_card(card):
        boba_id = card.get("bobaId")
        cn = card.get("cardNumber")
        image_file = card.get("imageFile")
        if not (boba_id and cn and image_file):
            return
        candidates = bv_index.get(cn, [])
        if not candidates:
            with counters_lock: counters["no_bv_row"] += 1
            return
        row = match_bv_row(card, candidates)
        if not row:
            with counters_lock: counters["no_bv_row"] += 1
            return
        with counters_lock: counters["matched"] += 1
        bv_url = row["image_url"]

        if args.dry_run:
            with succeeded_lock: succeeded_boba_ids.add(boba_id)
            return

        bv_bytes = download_bv_image(bv_url)
        if not bv_bytes:
            with counters_lock: counters["download_err"] += 1
            return
        try:
            full_bytes = to_webp(bv_bytes, max_long_side=1200, quality=85)
            thumb_bytes = to_webp(bv_bytes, max_long_side=200, quality=80)
        except Exception as e:
            print(f"    PIL failed for {boba_id}: {e}", file=sys.stderr)
            with counters_lock: counters["download_err"] += 1
            return

        ok1 = upload_to_r2(r2, bucket, f"full/{image_file}",   full_bytes)
        ok2 = upload_to_r2(r2, bucket, f"thumbs/{image_file}", thumb_bytes)
        if not (ok1 and ok2):
            with counters_lock: counters["upload_err"] += 1
            return

        with succeeded_lock: succeeded_boba_ids.add(boba_id)

    if args.workers <= 1 or args.dry_run:
        for c in work:
            process_card(c)
    else:
        completed = 0
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = [pool.submit(process_card, c) for c in work]
            for f in as_completed(futures):
                f.result()
                completed += 1
                if completed % 200 == 0:
                    elapsed = time.time() - started_at
                    rate = completed / elapsed
                    eta = (len(work) - completed) / rate if rate > 0 else 0
                    print(f"  [{completed:5d}/{len(work):,}] succeeded={len(succeeded_boba_ids)} "
                          f"rate={rate:.1f}/s elapsed={elapsed:.0f}s eta={eta:.0f}s")
    matched      = counters["matched"]
    no_bv_row    = counters["no_bv_row"]
    download_err = counters["download_err"]
    upload_err   = counters["upload_err"]

    if not args.dry_run and succeeded_boba_ids:
        counts = update_catalogs(succeeded_boba_ids, from_source=args.from_source, new_source=args.new_source)
        print("Catalog updates:")
        for path, n in counts.items():
            print(f"  {path}: {n} rows flipped")

    elapsed = time.time() - started_at
    print()
    print(f"=== Summary (elapsed {elapsed:.0f}s) ===")
    print(f"  processed:      {len(work):,}")
    print(f"  matched (BV):   {matched:,}")
    print(f"  succeeded:      {len(succeeded_boba_ids):,}")
    print(f"  no BV row:      {no_bv_row:,}")
    print(f"  download err:   {download_err:,}")
    print(f"  upload err:     {upload_err:,}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
