#!/usr/bin/env python3
"""
stage_a_scrape_bv.py — Stage A: source candidates from BazookaVault CDN

BV has the most comprehensive card-image coverage of any source we can
reach. Auth was needed once to crawl BV's card pages and produce the
URL→cardNumber mapping (`pipeline/data/bv_scan_results.csv`); the
images themselves live at `https://images.bazookavault.com/...` and
are public.

This sourcer joins the BV CSV against cards.json's missing-art set
and downloads the matching image for each. Far higher hit rate than
eBay (long-tail listings rarely exist).

ENV: SUPABASE_URL, SUPABASE_SERVICE_KEY, R2_ACCOUNT_ID, R2_ACCESS_KEY,
     R2_SECRET_KEY
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Optional

import boto3
import requests
from botocore.config import Config
from dotenv import load_dotenv
from supabase import Client, create_client

load_dotenv(Path(__file__).resolve().parents[2] / ".env")


CDN_STAGING_PREFIX = "staging/scrape/bv"
USER_AGENT         = "Mozilla/5.0 (compatible; BoBA-Pipeline/1.0)"
BV_CSV_PATH        = Path(__file__).resolve().parents[1] / "data" / "bv_scan_results.csv"


# ─── Helpers ──────────────────────────────────────────────────────────────

def make_r2_client(account_id, access_key, secret_key):
    return boto3.client(
        "s3",
        endpoint_url=f"https://{account_id}.r2.cloudflarestorage.com",
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(signature_version="s3v4", retries={"max_attempts": 3}),
    )


def load_cards_json(repo_root: Path) -> list[dict]:
    cards_path = repo_root / "assets" / "data" / "cards.json"
    if cards_path.exists():
        return json.loads(cards_path.read_text())
    return json.loads(subprocess.check_output(
        ["git", "-C", str(repo_root), "show", "HEAD:assets/data/cards.json"],
        text=True,
    ))


def boba_id_for(card: dict) -> str:
    # v3 5-field formula (DECISIONS.md #057). Element is the 5th field
    # and disambiguates FIRE/GLOW weapon-variant pairs. Must match
    # pipeline_image_candidates.target_boba_id post-v3-migration.
    cn = (card.get("cardNumber") or "").strip()
    hero = (card.get("hero") or card.get("name") or "").strip()
    treat = (card.get("treatment") or "").strip()
    var = (card.get("variation") or "").strip()
    elem = (card.get("element") or "").strip()
    return f"{cn}-{hero}-{treat}-{var}-{elem}"


def index_bv_rows() -> dict[str, list[dict]]:
    """Index BV rows by external_card_number → list of candidate rows.

    Filters to rows where:
      - is_placeholder = '0' (real card art, not a BV placeholder)
      - image_url is set

    download_status is intentionally NOT filtered — values are:
      'ok'      → the scraper downloaded successfully
      'exists'  → URL reachable but file already on disk (still valid)
      ''        → never attempted (added after scrape; URL likely valid)
    All three are downloadable today; we'll detect dead URLs at fetch
    time. Filtering on 'ok' alone dropped from 23,660 valid rows to
    5,687 — most of BV's coverage was being silently skipped.

    Multiple BV rows can map to one cardNumber (different treatments).
    We keep them all and let the matcher pick by hero/name.
    """
    if not BV_CSV_PATH.exists():
        raise FileNotFoundError(f"BV CSV not at {BV_CSV_PATH}")
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


def match_bv_to_card(card: dict, bv_rows: list[dict]) -> Optional[dict]:
    """From the candidate BV rows for a cardNumber, pick the row whose
    `name` best matches the catalog card's hero/name. Returns the row
    or None if nothing matches well enough."""
    target = ((card.get("hero") or card.get("name") or "")
              .strip().lower().replace("’", "'"))
    if not target:
        return bv_rows[0] if bv_rows else None  # fallback: first row

    # Normalize for fuzzy match: alnum-only lowercase
    def norm(s: str) -> str:
        return "".join(ch for ch in s.lower() if ch.isalnum())
    nt = norm(target)

    # Score each row: exact match > prefix > substring
    best, best_score = None, -1
    for r in bv_rows:
        name = (r.get("name") or "").strip()
        nn = norm(name)
        if not nn:
            continue
        if nt == nn:
            score = 3
        elif nn.startswith(nt) or nt.startswith(nn):
            score = 2
        elif nt in nn or nn in nt:
            score = 1
        else:
            score = 0
        if score > best_score:
            best_score, best = score, r
    return best if best_score >= 1 else None


def filter_to_actionable(cards, supabase, skip_recent_days):
    boba_ids = [boba_id_for(c) for c in cards]
    CHUNK = 50
    busy, cooled = set(), set()
    for i in range(0, len(boba_ids), CHUNK):
        chunk = boba_ids[i:i + CHUNK]
        res = (supabase.table("pipeline_image_candidates")
               .select("target_boba_id")
               .in_("target_boba_id", chunk)
               .in_("state", ["discovered", "downloaded", "cropped",
                              "recognized", "accepted", "review"])
               .execute()).data or []
        busy.update(r["target_boba_id"] for r in res if r.get("target_boba_id"))

    cutoff = (datetime.now(timezone.utc) - timedelta(days=skip_recent_days)).isoformat()
    for i in range(0, len(boba_ids), CHUNK):
        chunk = boba_ids[i:i + CHUNK]
        res = (supabase.table("pipeline_card_images")
               .select("boba_id,last_attempted_at")
               .in_("boba_id", chunk)
               .gte("last_attempted_at", cutoff)
               .execute()).data or []
        cooled.update(r["boba_id"] for r in res)

    return [c for c in cards
            if boba_id_for(c) not in busy
            and boba_id_for(c) not in cooled]


def download_image(url: str) -> Optional[bytes]:
    try:
        resp = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=20)
        resp.raise_for_status()
        return resp.content
    except Exception:
        return None


# ─── Main ─────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--limit", type=int, default=500)
    ap.add_argument("--skip-recent-days", type=int, default=7)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    repo_root = Path(args.repo_root).resolve()
    supabase = create_client(
        os.environ["SUPABASE_URL"].strip(),
        os.environ["SUPABASE_SERVICE_KEY"].strip(),
    )
    r2 = make_r2_client(
        os.environ["R2_ACCOUNT_ID"].strip(),
        os.environ["R2_ACCESS_KEY"].strip(),
        os.environ["R2_SECRET_KEY"].strip(),
    )
    bucket = os.environ.get("R2_BUCKET", "boba-card-images").strip()

    run_id = None
    if not args.dry_run:
        run = supabase.table("pipeline_runs").insert({
            "run_type": "scrape",
            "gh_actions_run_id": os.environ.get("GITHUB_RUN_ID"),
            "summary": {"source": "bazookavault-csv-join"},
        }).execute()
        run_id = run.data[0]["id"]
        print(f"run_id: {run_id}")

    # ─── STEP 1: load and filter cards.json to imageAvailable=false ──
    all_cards = load_cards_json(repo_root)
    missing = [c for c in all_cards if not c.get("imageAvailable")]
    print(f"cards.json catalog:           {len(all_cards):,}")
    print(f"  - imageAvailable=true:      {len(all_cards) - len(missing):,}")
    print(f"  - imageAvailable=false:     {len(missing):,}  ← targeting these")

    # ─── STEP 2: filter out already-active or recently-attempted ──
    actionable = filter_to_actionable(missing, supabase, args.skip_recent_days)
    print(f"  - busy/cooled filtered:     {len(missing) - len(actionable):,}")
    print(f"  - actionable this run:      {len(actionable):,}")

    # ─── STEP 3: load BV index + match ──
    print(f"\nloading BV index from {BV_CSV_PATH.name} …")
    bv_index = index_bv_rows()
    print(f"  BV cardNumbers with real images: {len(bv_index):,}")

    matched = []
    for c in actionable:
        cn = (c.get("cardNumber") or "").strip()
        if not cn or cn not in bv_index:
            continue
        bv = match_bv_to_card(c, bv_index[cn])
        if bv:
            matched.append((c, bv))
    print(f"  matched against BV:         {len(matched):,}")

    targets = matched[:args.limit]
    print(f"  fetching:                   {len(targets):,}")

    # ─── STEP 4: fetch + upload + insert ──
    inserted, skipped, errors = 0, 0, 0
    for i, (card, bv) in enumerate(targets):
        bid = boba_id_for(card)
        if i % 50 == 0:
            print(f"  [{i+1}/{len(targets)}] {bid}")

        if args.dry_run:
            inserted += 1
            continue

        img_bytes = download_image(bv["image_url"])
        if not img_bytes or len(img_bytes) < 4096:
            skipped += 1
            continue

        md5 = hashlib.md5(img_bytes).hexdigest()
        ext = ".webp" if bv["image_url"].lower().endswith(".webp") else ".jpg"
        r2_key = f"{CDN_STAGING_PREFIX}/{md5[:2]}/{md5}{ext}"

        try:
            try:
                r2.head_object(Bucket=bucket, Key=r2_key)
            except r2.exceptions.ClientError:
                ct = "image/webp" if ext == ".webp" else "image/jpeg"
                r2.put_object(Bucket=bucket, Key=r2_key, Body=img_bytes, ContentType=ct)

            supabase.table("pipeline_image_candidates").upsert({
                "source": "bazookavault",
                "source_url": bv["image_url"],
                "source_id": f"bv-{bv['bv_id']}-{md5[:8]}",
                "source_metadata": {
                    "bv_id": bv["bv_id"],
                    "name":  bv.get("name"),
                    "set":   bv.get("set"),
                    "type":  bv.get("type"),
                },
                "target_boba_id":     bid,
                "target_card_number": (card.get("cardNumber") or "").strip(),
                "raw_image_r2_key":   r2_key,
                "crop_image_r2_key":  r2_key,
                "image_md5":          md5,
                "state":              "cropped",
                "scraped_by_run_id":  run_id,
            }, on_conflict="source,source_id", ignore_duplicates=True).execute()
            inserted += 1
        except Exception as e:
            print(f"    ! failed for {bid}: {e}")
            errors += 1

        supabase.table("pipeline_card_images").upsert({
            "boba_id": bid,
            "has_image": False,
            "last_attempted_at": "now()",
            "attempt_count": 1,
        }, on_conflict="boba_id").execute()

    print(f"\n  inserted: {inserted}")
    print(f"  skipped (download failed): {skipped}")
    print(f"  errors:   {errors}")

    if not args.dry_run and run_id:
        supabase.table("pipeline_runs").update({
            "finished_at": "now()",
            "candidates_processed": len(targets),
            "candidates_accepted":  inserted,
            "errors_encountered":   errors,
            "summary": {"source": "bazookavault-csv-join",
                        "matched": len(matched), "inserted": inserted,
                        "skipped": skipped, "errors": errors},
        }).eq("id", run_id).execute()


if __name__ == "__main__":
    main()
