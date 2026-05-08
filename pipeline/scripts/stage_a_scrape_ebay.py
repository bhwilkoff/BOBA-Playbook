#!/usr/bin/env python3
"""
stage_a_scrape_ebay.py — Stage A: source new candidates from eBay

Reads cards.json, finds bobaIds with imageAvailable=false, queries eBay
search HTML for each (rate-limited), downloads top-N candidate images,
uploads them to R2 staging, and inserts pipeline_image_candidates rows
with target_boba_id set so Stage B's recognition can verify the actual
card matches what we asked for.

Uses HTML scraping (no eBay API auth required). Slower than the Browse
API but works from the Linux GH Actions runner without additional
secrets. Future iteration may extend the existing boba-ebay-proxy
Worker with a /scrape endpoint and switch to that.

USAGE
─────
    python pipeline/scripts/stage_a_scrape_ebay.py \\
        --limit             200 \\
        --candidates-per-card 3 \\
        --skip-recent-days  7

ENV (required):
    SUPABASE_URL, SUPABASE_SERVICE_KEY
    R2_ACCOUNT_ID, R2_ACCESS_KEY, R2_SECRET_KEY

Skips bobaIds that:
  • already have art in cards.json (imageAvailable=true)
  • already have ANY pipeline_image_candidates row in non-terminal state
    (don't waste eBay queries on cards that already have candidates
    waiting for Stage B)
  • were last attempted < `skip-recent-days` ago
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import re
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Optional

import boto3
import requests
from botocore.config import Config
from bs4 import BeautifulSoup
from dotenv import load_dotenv
from supabase import Client, create_client

load_dotenv(Path(__file__).resolve().parents[2] / ".env")


CDN_STAGING_PREFIX = "staging/scrape/ebay"

# Reasonable User-Agent so we look like a normal browser. eBay's HTML
# search responds to all major UAs; rotating helps avoid bot blocks
# but isn't strictly necessary at our query volume.
USER_AGENTS = [
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
]

EBAY_SEARCH_URL = "https://www.ebay.com/sch/i.html"


# ─── Helpers ──────────────────────────────────────────────────────────────

def make_r2_client(account_id, access_key, secret_key):
    return boto3.client(
        "s3",
        endpoint_url=f"https://{account_id}.r2.cloudflarestorage.com",
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(signature_version="s3v4", retries={"max_attempts": 3}),
    )


def load_missing_art(repo_root: Path) -> list[dict]:
    """Return cards.json entries with imageAvailable=false."""
    cards_path = repo_root / "assets" / "data" / "cards.json"
    if not cards_path.exists():
        # Fallback: pull HEAD from git
        text = subprocess.check_output(
            ["git", "-C", str(repo_root), "show", "HEAD:assets/data/cards.json"],
            text=True,
        )
        cards = json.loads(text)
    else:
        cards = json.loads(cards_path.read_text())
    return [c for c in cards if not c.get("imageAvailable")]


def boba_id_for(card: dict) -> str:
    cn = (card.get("cardNumber") or "").strip()
    hero = (card.get("hero") or card.get("name") or "").strip()
    treat = (card.get("treatment") or "").strip()
    var = (card.get("variation") or "").strip()
    return f"{cn}-{hero}-{treat}-{var}"


def filter_to_actionable(cards: list[dict], supabase: Client,
                         skip_recent_days: int) -> list[dict]:
    """Drop cards that have active candidates or were tried recently.

    Chunks are small (50 bobaIds per query) because PostgREST encodes
    `.in_()` lists into the URL — 1000+ bobaIds explode the URL past
    the server's max length and trigger 400 'JSON could not be
    generated'. 50 stays under ~4KB per request.
    """
    boba_ids = [boba_id_for(c) for c in cards]
    CHUNK = 50

    busy = set()
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
    cooled = set()
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


def build_query(card: dict) -> str:
    cn = (card.get("cardNumber") or "").strip()
    hero = (card.get("hero") or card.get("name") or "").strip()
    return f"{cn} {hero} BOBA"


def scrape_ebay(query: str, top_n: int = 3) -> list[dict]:
    """Hit eBay's HTML search and parse the first `top_n` listing image
    URLs. Returns [{listing_id, image_url, title, listing_url}]."""
    params = {"_nkw": query, "_sop": "12", "_ipg": "60"}
    headers = {"User-Agent": random.choice(USER_AGENTS)}
    try:
        resp = requests.get(EBAY_SEARCH_URL, params=params, headers=headers,
                            timeout=15)
        resp.raise_for_status()
    except Exception as e:
        print(f"  ! ebay fetch failed for {query!r}: {e}")
        return []

    soup = BeautifulSoup(resp.text, "html.parser")
    items = []
    for li in soup.select("li.s-item")[:30]:
        if len(items) >= top_n:
            break
        img = li.select_one("img.s-item__image-img") or li.select_one("img")
        link = li.select_one("a.s-item__link")
        if not img or not link:
            continue
        # Lazy-loaded eBay images put the real URL in data-src or data-defer-load
        url = (img.get("data-defer-load") or img.get("data-src")
               or img.get("src"))
        if not url or "ir.ebaystatic.com" in url:
            continue
        # Promote thumb to full-size by stripping size suffix (...s-l140.jpg → s-l1600)
        url = re.sub(r"s-l\d+\.", "s-l1600.", url)
        href = link.get("href") or ""
        m = re.search(r"/itm/(?:[^/]+/)?(\d+)", href)
        listing_id = m.group(1) if m else None
        title = (link.get_text() or "").strip()
        if not listing_id or "Shop on eBay" in title:
            continue
        items.append({
            "listing_id": listing_id,
            "image_url": url,
            "title": title,
            "listing_url": href,
        })
    return items


def download_image(url: str) -> Optional[bytes]:
    headers = {"User-Agent": random.choice(USER_AGENTS)}
    try:
        resp = requests.get(url, headers=headers, timeout=20)
        resp.raise_for_status()
        return resp.content
    except Exception:
        return None


# ─── Main ─────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo-root", default=".",
                    help="Path to BOBA-Playbook checkout (default: cwd)")
    ap.add_argument("--limit", type=int, default=200,
                    help="Max cards to query this run (default 200)")
    ap.add_argument("--candidates-per-card", type=int, default=3,
                    help="Top N images per card (default 3)")
    ap.add_argument("--skip-recent-days", type=int, default=7,
                    help="Skip cards last attempted within N days (default 7)")
    ap.add_argument("--query-delay", type=float, default=1.0,
                    help="Sleep N seconds between eBay queries (default 1.0)")
    ap.add_argument("--dry-run", action="store_true",
                    help="Discover + plan, don't fetch eBay or write Supabase")
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

    # ─── Open run ──
    run_id: Optional[str] = None
    if not args.dry_run:
        run = supabase.table("pipeline_runs").insert({
            "run_type": "scrape",
            "gh_actions_run_id":  os.environ.get("GITHUB_RUN_ID"),
            "summary": {"source": "ebay-html-scrape"},
        }).execute()
        run_id = run.data[0]["id"]
        print(f"run_id: {run_id}")

    # ─── Discover ──
    missing = load_missing_art(repo_root)
    print(f"cards with imageAvailable=false: {len(missing):,}")
    actionable = filter_to_actionable(missing, supabase, args.skip_recent_days)
    print(f"  - busy/cooled filtered:  {len(missing) - len(actionable):,}")
    print(f"  - actionable this run:   {len(actionable):,}")

    targets = actionable[:args.limit]
    print(f"  - querying:              {len(targets):,}")

    # ─── Scrape + upload ──
    inserted, skipped, errors = 0, 0, 0
    for i, card in enumerate(targets):
        bid = boba_id_for(card)
        query = build_query(card)
        if i % 20 == 0:
            print(f"  [{i+1}/{len(targets)}] {bid}  q={query!r}")

        if args.dry_run:
            time.sleep(0.05)
            continue

        items = scrape_ebay(query, top_n=args.candidates_per_card)
        if not items:
            skipped += 1
            time.sleep(args.query_delay)
            continue

        for item in items:
            img_bytes = download_image(item["image_url"])
            if not img_bytes or len(img_bytes) < 4096:
                continue
            md5 = hashlib.md5(img_bytes).hexdigest()
            r2_key = f"{CDN_STAGING_PREFIX}/{md5[:2]}/{md5}.jpg"

            try:
                # Skip if already uploaded (idempotent)
                try:
                    r2.head_object(Bucket=bucket, Key=r2_key)
                except r2.exceptions.ClientError:
                    r2.put_object(Bucket=bucket, Key=r2_key, Body=img_bytes,
                                  ContentType="image/jpeg")

                # Upsert candidate row
                supabase.table("pipeline_image_candidates").upsert({
                    "source": "ebay",
                    "source_url": item["listing_url"],
                    "source_id": f"ebay-{item['listing_id']}-{md5[:8]}",
                    "source_metadata": {
                        "title": item["title"],
                        "query": query,
                    },
                    "target_boba_id":   bid,
                    "target_card_number": (card.get("cardNumber") or "").strip(),
                    "raw_image_r2_key":  r2_key,
                    "crop_image_r2_key": r2_key,
                    "image_md5":         md5,
                    "state":             "cropped",
                    "scraped_by_run_id": run_id,
                }, on_conflict="source,source_id", ignore_duplicates=True).execute()
                inserted += 1
            except Exception as e:
                print(f"    ! upload/insert failed for {bid}: {e}")
                errors += 1

        # Stamp last_attempted_at on pipeline_card_images
        supabase.table("pipeline_card_images").upsert({
            "boba_id":           bid,
            "has_image":         False,
            "last_attempted_at": "now()",
            "attempt_count":     1,
        }, on_conflict="boba_id").execute()

        time.sleep(args.query_delay)

    print(f"\n  inserted: {inserted}")
    print(f"  skipped (no eBay results): {skipped}")
    print(f"  errors:   {errors}")

    if not args.dry_run and run_id:
        supabase.table("pipeline_runs").update({
            "finished_at":          "now()",
            "candidates_processed": len(targets),
            "candidates_accepted":  inserted,
            "errors_encountered":   errors,
            "summary": {
                "source": "ebay-html-scrape",
                "queried": len(targets),
                "inserted": inserted,
                "skipped": skipped,
                "errors": errors,
            },
        }).eq("id", run_id).execute()


if __name__ == "__main__":
    main()
