#!/usr/bin/env python3
"""
stage_a_scrape_radish.py — Stage A: source candidates from Radish PriceGuide

Radish hosts comprehensive card-image coverage (better long-tail than
eBay because they list cards regardless of recent sales activity).
Card pages embed Cloudinary URLs that we can extract + download.

URL pattern: https://radishpriceguide.com/boba/{year}/{slug}/{hero}/{cardNumber}
Year/slug pairs come from a fixed list (RADISH_NAMESPACES) since
Radish doesn't expose a clean catalog API. We probe namespaces in order
until one returns 200, then extract the Cloudinary `image/upload`
URL from the page HTML.

ENV: SUPABASE_URL, SUPABASE_SERVICE_KEY, R2_ACCOUNT_ID, R2_ACCESS_KEY,
     R2_SECRET_KEY
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import time
import urllib.parse
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Optional

import boto3
import requests
from botocore.config import Config
from dotenv import load_dotenv
from supabase import Client, create_client

load_dotenv(Path(__file__).resolve().parents[2] / ".env")


CDN_STAGING_PREFIX = "staging/scrape/radish"
RADISH_BASE        = "https://radishpriceguide.com/boba"
USER_AGENT         = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

# Mirrors workers/ebay-proxy/worker.js RADISH_NAMESPACES.
# Cards are scattered across these (year, slug) pairs; we probe in order
# of likely match by recency.
RADISH_NAMESPACES = [
    ("2026", "Griffey_Edition"),
    ("2025", "Alpha_Update"),
    ("2025", "Alpha_Blast"),
    ("2025", "World_Champions"),
    ("2025", "Big_League_Chew"),
    ("2025", "Promo_Cards"),
    ("2024", "Alpha_Edition"),
    ("2024", "World_Champions"),
    ("2024", "National_24_Starter_Set"),
    ("2024", "Battle_Trainer_Kit"),
    ("2024", "Promo_Cards"),
    ("2026", "Promo_Cards"),
]

# Hint table: catalog `set` field → most-likely (year, slug). Tried
# first per card to cut average probe count from 12 → 1-2.
SET_TO_NAMESPACE = {
    "Griffey Edition":            ("2026", "Griffey_Edition"),
    "Alpha Update":               ("2025", "Alpha_Update"),
    "Alpha Blast":                ("2025", "Alpha_Blast"),
    "Alpha Edition":              ("2024", "Alpha_Edition"),
    "World Champions":            ("2025", "World_Champions"),
    "Big League Chew":            ("2025", "Big_League_Chew"),
    "Promo Cards":                ("2025", "Promo_Cards"),
    "National 24 Starter Set":    ("2024", "National_24_Starter_Set"),
    "Battle Trainer Kit":         ("2024", "Battle_Trainer_Kit"),
}

CLOUDINARY_RE = re.compile(
    r'https://res\.cloudinary\.com/[^"\s]*?/boba-cards/[a-z0-9]+\.(?:jpg|png|webp)',
    re.IGNORECASE,
)


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
    cards_path = repo_root / "assets" / "data" / "cards.json"
    if cards_path.exists():
        cards = json.loads(cards_path.read_text())
    else:
        cards = json.loads(subprocess.check_output(
            ["git", "-C", str(repo_root), "show", "HEAD:assets/data/cards.json"],
            text=True,
        ))
    return [c for c in cards if not c.get("imageAvailable")]


def boba_id_for(card: dict) -> str:
    cn = (card.get("cardNumber") or "").strip()
    hero = (card.get("hero") or card.get("name") or "").strip()
    treat = (card.get("treatment") or "").strip()
    var = (card.get("variation") or "").strip()
    return f"{cn}-{hero}-{treat}-{var}"


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


def candidate_namespaces(card: dict) -> list[tuple[str, str]]:
    """Return the namespaces to probe for this card, hinted set first."""
    s = (card.get("set") or "").strip()
    hint = SET_TO_NAMESPACE.get(s)
    if hint:
        return [hint] + [n for n in RADISH_NAMESPACES if n != hint]
    return list(RADISH_NAMESPACES)


def hero_variants(card: dict) -> list[str]:
    """Radish hero spelling can use space or hyphen — try both."""
    raw = (card.get("hero") or card.get("name") or "").strip()
    if not raw:
        return []
    out = [raw]
    if "-" in raw:
        out.append(raw.replace("-", " "))
    if " " in raw:
        out.append(raw.replace(" ", "-"))
    return out


def fetch_radish_card_image(card: dict, max_probes: int = 6) -> Optional[tuple[str, str]]:
    """Probe Radish URLs until one returns 200 with a Cloudinary image.

    Returns (cloudinary_url, source_url) or None.
    """
    cn = (card.get("cardNumber") or "").strip()
    if not cn:
        return None

    headers = {"User-Agent": USER_AGENT}
    namespaces = candidate_namespaces(card)
    heroes = hero_variants(card)
    if not heroes:
        return None

    probes = 0
    for year, slug in namespaces:
        for hero in heroes:
            if probes >= max_probes:
                return None
            probes += 1
            url = f"{RADISH_BASE}/{year}/{slug}/{urllib.parse.quote(hero)}/{urllib.parse.quote(cn)}"
            try:
                resp = requests.get(url, headers=headers, timeout=12)
            except Exception:
                continue
            if resp.status_code != 200:
                continue
            m = CLOUDINARY_RE.search(resp.text)
            if not m:
                continue
            # Strip Cloudinary transformation suffix to get original-quality
            # source. The page embeds w_768,c_limit,q_auto,f_auto/v.../{id}
            # — we want just .../upload/v.../{id} for highest fidelity.
            img_url = m.group(0)
            img_url = re.sub(
                r"/image/upload/[^/]+/v(\d+)/",
                r"/image/upload/v\1/",
                img_url,
            )
            return img_url, url
    return None


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
    ap.add_argument("--limit", type=int, default=200)
    ap.add_argument("--skip-recent-days", type=int, default=7)
    ap.add_argument("--probe-delay", type=float, default=0.3,
                    help="Seconds between Radish requests (default 0.3)")
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
            "summary": {"source": "radish-html-scrape"},
        }).execute()
        run_id = run.data[0]["id"]
        print(f"run_id: {run_id}")

    missing = load_missing_art(repo_root)
    print(f"cards with imageAvailable=false: {len(missing):,}")
    actionable = filter_to_actionable(missing, supabase, args.skip_recent_days)
    print(f"  - actionable this run:   {len(actionable):,}")
    targets = actionable[:args.limit]
    print(f"  - querying:              {len(targets):,}")

    inserted, skipped, errors = 0, 0, 0
    for i, card in enumerate(targets):
        bid = boba_id_for(card)
        if i % 20 == 0:
            print(f"  [{i+1}/{len(targets)}] {bid}")

        if args.dry_run:
            time.sleep(0.05)
            continue

        result = fetch_radish_card_image(card)
        if not result:
            skipped += 1
            time.sleep(args.probe_delay)
            continue

        img_url, source_url = result
        img_bytes = download_image(img_url)
        if not img_bytes or len(img_bytes) < 4096:
            skipped += 1
            time.sleep(args.probe_delay)
            continue

        md5 = hashlib.md5(img_bytes).hexdigest()
        ext = ".webp" if img_url.lower().endswith(".webp") else ".jpg"
        r2_key = f"{CDN_STAGING_PREFIX}/{md5[:2]}/{md5}{ext}"

        try:
            try:
                r2.head_object(Bucket=bucket, Key=r2_key)
            except r2.exceptions.ClientError:
                ct = "image/webp" if ext == ".webp" else "image/jpeg"
                r2.put_object(Bucket=bucket, Key=r2_key, Body=img_bytes, ContentType=ct)

            supabase.table("pipeline_image_candidates").upsert({
                "source": "radish",
                "source_url": source_url,
                "source_id": f"radish-{md5}",
                "source_metadata": {"cloudinary_url": img_url},
                "target_boba_id": bid,
                "target_card_number": (card.get("cardNumber") or "").strip(),
                "raw_image_r2_key": r2_key,
                "crop_image_r2_key": r2_key,
                "image_md5": md5,
                "state": "cropped",
                "scraped_by_run_id": run_id,
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

        time.sleep(args.probe_delay)

    print(f"\n  inserted: {inserted}")
    print(f"  skipped (no Radish hit): {skipped}")
    print(f"  errors:   {errors}")

    if not args.dry_run and run_id:
        supabase.table("pipeline_runs").update({
            "finished_at": "now()",
            "candidates_processed": len(targets),
            "candidates_accepted": inserted,
            "errors_encountered": errors,
            "summary": {"source": "radish-html-scrape",
                        "queried": len(targets), "inserted": inserted,
                        "skipped": skipped, "errors": errors},
        }).eq("id", run_id).execute()


if __name__ == "__main__":
    main()
