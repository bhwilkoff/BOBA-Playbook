#!/usr/bin/env python3
"""
comc_direct_sourcer.py — Tier-3 image source: COMC.com listings.

Why this exists:
  After BV → direct-eBay → Radish, ~3-4k missing-art records remain
  un-sourced. COMC has 931 BoBA listings (verified 2026-04-29) covering
  every observed set + treatment, with cardNumbers in URLs that match
  cards.json EXACTLY (MBFA-31, BFA-63, GLBF-484, etc.). High-resolution
  scans live on a stable CDN. This script slots into the same review-queue
  pipeline as ebay_direct_sourcer.py.

Pipeline contract:
  reads   unified-cards/data/missing_art_targets.json   (seed list)
  appends ebay-missing-downloads/radish_ebay_scan.csv   (shared schema —
              ebay_review_server.py picks up source="comc" rows
              alongside radish + direct-ebay without modification)
  writes  ebay-review/needs-review/{bobaIdSlug}__comc-{itemId}__{n}.jpg
          ebay-missing-downloads/comc_progress.json     (resume state)

Usage:
  python3 comc_direct_sourcer.py scan       # find COMC listings for missing cards
  python3 comc_direct_sourcer.py download   # pull images for scanned listings
  python3 comc_direct_sourcer.py all        # scan + download
  python3 comc_direct_sourcer.py status     # progress + hit rate

Options:
  --limit N              only process first N missing cards
  --cards cn1,cn2,…      restrict to specific cardNumbers
  --cards-file path      file with one cardNumber per line
  --max-per-card N       keep at most N listings per card (default 3)
  --force                re-scan/re-download even when already recorded

Anti-bot:
  COMC returns 403 to unbranded User-Agent strings. We send the same
  Chrome-shaped header set the Whatnot direct sourcer uses; cookies are
  NOT required for the public listing data we consume.

  The script intentionally throttles to ~1 req/sec to stay polite.
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import os
import pathlib
import re
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime
from urllib.parse import quote_plus, urljoin

import requests

# ── Paths (mirror ebay_direct_sourcer.py) ────────────────────────────────────
ROOT         = pathlib.Path(__file__).resolve().parent
DATA         = ROOT / "unified-cards" / "data"
TARGETS      = DATA / "missing_art_targets.json"
OUT_DIR      = ROOT / "ebay-missing-downloads"
SCAN_CSV     = OUT_DIR / "radish_ebay_scan.csv"
PROGRESS     = OUT_DIR / "comc_progress.json"
NEEDS_REVIEW = ROOT / "ebay-review" / "needs-review"
VERIFIED     = ROOT / "ebay-verified" / "images"

OUT_DIR.mkdir(parents=True, exist_ok=True)
NEEDS_REVIEW.mkdir(parents=True, exist_ok=True)
VERIFIED.mkdir(parents=True, exist_ok=True)

# ── Single source of truth for bobaId ────────────────────────────────────────
sys.path.insert(0, str(ROOT / "scripts"))
try:
    from boba_id import boba_id as _boba_id, slug_for_file as _slug_for_file
except ImportError:
    # Fallback for standalone testing — keep aligned with scripts/boba_id.py
    def _boba_id(card: dict) -> str:
        cn    = str(card.get("cardNumber") or "").strip()
        hero  = str(card.get("hero") or card.get("name") or "").strip()
        treat = str(card.get("treatment") or "").strip()
        var   = str(card.get("variation") or "").strip()
        return f"{cn}-{hero}-{treat}-{var}"

    def _slug_for_file(bid: str) -> str:
        s = re.sub(r"[^A-Za-z0-9\-]+", "_", bid or "")
        s = re.sub(r"_+", "_", s)
        return s.strip("_")


# ── COMC HTTP layer ──────────────────────────────────────────────────────────
COMC_BASE = "https://www.comc.com"
IMG_BASE  = "https://img.comc.com"
SOURCE_TAG = "comc"   # value written into scan CSV's `source` column
REQ_DELAY = 1.0       # seconds between requests, polite throttle
TIMEOUT   = 20

HEADERS = {
    "User-Agent":
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/127.0.0.0 Safari/537.36",
    "Accept":
        "text/html,application/xhtml+xml,application/xml;q=0.9,"
        "image/avif,image/webp,image/apng,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Cache-Control": "no-cache",
    "Sec-Fetch-Dest": "document",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-Site": "none",
    "Sec-Fetch-User": "?1",
    "Upgrade-Insecure-Requests": "1",
}

IMG_HEADERS = {
    **HEADERS,
    "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
    "Sec-Fetch-Dest": "image",
    "Sec-Fetch-Mode": "no-cors",
    "Sec-Fetch-Site": "same-site",
    "Referer": COMC_BASE + "/",
}


# ── HTML parsing — DOM-regex (no JSON payload, verified) ─────────────────────
#
# A search result row in the rendered HTML wraps each listing in an <a> whose
# href points at a /Cards/Gaming/{year}/{set_slug}/{cardNumber}/{hero}/{itemId}/...
# path. The detail page reachable from that anchor exposes the image URL on
# the img.comc.com CDN. Pattern is stable across the 4+ samples inspected
# during the 2026-04-29 recon.

LISTING_HREF_RE = re.compile(
    r'<a[^>]*href="(/Cards/Gaming/(\d{4})/([^/]+)/([^/]+)/([^/]+)/(\d+)/'
    r'(Ungraded|Graded)/COMC_CCG/([^"]+))"',
    re.IGNORECASE,
)

PRICE_NEAR_HREF_RE = re.compile(
    r'\$(\d{1,4}(?:,\d{3})*(?:\.\d{2}))'
)

# Detail page — image URL pattern. Two variants observed:
#   <a href="…?id=UUID&size=zoom"…
#   <img src="https://img.comc.com/i/Gaming/…?id=UUID&size=…">
DETAIL_IMG_RE = re.compile(
    r'https://img\.comc\.com/i/Gaming/[^?\s"]+\?id=[a-f0-9-]+(?:&size=\w+)?',
    re.IGNORECASE,
)


# ── Listing dataclass ────────────────────────────────────────────────────────
@dataclass
class ComcListing:
    item_id:      str
    href:         str
    detail_url:   str
    year:         str
    set_slug:     str           # underscore form from /Cards/Gaming/.../{set_slug}/
    card_number:  str           # exact match against cards.json cardNumber
    hero_slug:    str           # underscore form from URL
    grading:      str           # "Ungraded" | "Graded"
    condition:    str           # "NM", "PSA9", etc.
    asking_price: float | None  # USD, parsed from page near the anchor
    image_url:    str = ""      # populated during download phase if needed


# ── Progress / scan state ────────────────────────────────────────────────────
def load_progress() -> dict:
    if PROGRESS.exists():
        return json.loads(PROGRESS.read_text(encoding="utf-8"))
    return {"scanned_boba": [], "last_run": None, "stats": {}}

def save_progress(p: dict) -> None:
    p["last_run"] = datetime.utcnow().isoformat() + "Z"
    PROGRESS.write_text(json.dumps(p, indent=2, ensure_ascii=False))

def load_targets() -> list[dict]:
    if not TARGETS.exists():
        raise FileNotFoundError(
            f"{TARGETS} not found — run scripts/regen_missing_targets.py first"
        )
    data = json.loads(TARGETS.read_text(encoding="utf-8"))
    return data.get("all_missing") or []

def existing_scan_keys() -> set[tuple[str, str]]:
    """Return {(cardNumber, listing_id)} already in the shared scan CSV.

    listing_id for COMC rows is "comc-{itemId}".
    """
    if not SCAN_CSV.exists():
        return set()
    out = set()
    with SCAN_CSV.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            lid = (r.get("listing_id") or "").strip()
            cn  = (r.get("cardNumber") or "").strip()
            if lid and cn:
                out.add((cn, lid))
    return out

def already_verified_bobaids() -> set[str]:
    if not VERIFIED.exists():
        return set()
    return {
        p.stem for p in VERIFIED.iterdir()
        if p.is_file() and p.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp")
    }


# ── HTTP fetchers ────────────────────────────────────────────────────────────
def make_session() -> requests.Session:
    s = requests.Session()
    s.headers.update(HEADERS)
    return s


def fetch_html(session: requests.Session, url: str) -> str | None:
    try:
        time.sleep(REQ_DELAY)
        r = session.get(url, timeout=TIMEOUT)
        if r.status_code == 200:
            return r.text
        if r.status_code == 403:
            sys.stderr.write(f"[COMC] 403 — anti-bot rejected our headers? {url}\n")
        elif r.status_code == 404:
            return ""  # legitimately no card; cache as empty
        else:
            sys.stderr.write(f"[COMC] HTTP {r.status_code} for {url}\n")
    except requests.RequestException as e:
        sys.stderr.write(f"[COMC] fetch error for {url}: {e}\n")
    return None


def search_listings_for_card(session: requests.Session,
                              card_number: str) -> list[ComcListing]:
    """Fetch the search-results page filtered to a specific cardNumber.

    URL: /Cards,i100,={cardNumber}  — verified to return exactly the rows
    matching that cardNumber (1-of-1 for unique cards on 2026-04-29 recon).
    """
    url = f"{COMC_BASE}/Cards,i100,={quote_plus(card_number)}"
    html = fetch_html(session, url)
    if not html:
        return []

    # Walk the listing anchors. Each match yields the full structured row
    # we need (year, set_slug, cardNumber, hero, itemId, grading, condition).
    listings: list[ComcListing] = []
    seen_item_ids: set[str] = set()

    for m in LISTING_HREF_RE.finditer(html):
        href, year, set_slug, cn_in_url, hero_slug, item_id, grading, condition = m.groups()
        if cn_in_url != card_number:
            # COMC's search is permissive ("MBFA-31" can also match "MBFA-310")
            # — only keep exact-match rows.
            continue
        if item_id in seen_item_ids:
            continue
        seen_item_ids.add(item_id)

        # Look ahead a bit in the HTML for the asking price near this anchor.
        end = m.end()
        window = html[end:end + 1500]
        price_m = PRICE_NEAR_HREF_RE.search(window)
        price = None
        if price_m:
            try:
                price = float(price_m.group(1).replace(",", ""))
            except ValueError:
                price = None

        listings.append(ComcListing(
            item_id=item_id,
            href=href,
            detail_url=urljoin(COMC_BASE, href),
            year=year,
            set_slug=set_slug,
            card_number=cn_in_url,
            hero_slug=hero_slug,
            grading=grading,
            condition=condition,
            asking_price=price,
        ))

    return listings


def fetch_detail_image_url(session: requests.Session,
                            listing: ComcListing) -> str | None:
    """Fetch a card-detail page and return its primary img.comc.com URL."""
    html = fetch_html(session, listing.detail_url)
    if not html:
        return None
    m = DETAIL_IMG_RE.search(html)
    if not m:
        return None
    url = m.group(0)
    # Prefer 4× zoom; rewrite size param if missing.
    if "size=" not in url:
        sep = "&" if "?" in url else "?"
        url = f"{url}{sep}size=zoom"
    return url


# ── Scan phase ──────────────────────────────────────────────────────────────
SCAN_FIELDS = [
    # Mirror exactly the schema in ebay_direct_sourcer.py so the review
    # server reads source="comc" rows alongside radish + direct-ebay.
    "bobaId", "cardNumber", "hero", "element", "power", "treatment",
    "variation", "subSet", "radishUrl", "listing_id", "ebay_url",
    "sold_date", "rank",
    "title", "image_url", "match_score", "source",
    "query_used", "query_tier",
]


def scan_csv_existing_listings_for_card(card_number: str) -> set[str]:
    """Return the listing_ids for a specific cardNumber already in scan CSV.
    (Used to skip already-recorded listings on resume.)"""
    if not SCAN_CSV.exists():
        return set()
    out: set[str] = set()
    with SCAN_CSV.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if (r.get("cardNumber") or "").strip() != card_number:
                continue
            lid = (r.get("listing_id") or "").strip()
            if lid:
                out.add(lid)
    return out


def cmd_scan(args):
    targets = load_targets()
    if args.cards or args.cards_file:
        wanted = set()
        if args.cards:
            wanted.update(c.strip() for c in args.cards.split(",") if c.strip())
        if args.cards_file and os.path.exists(args.cards_file):
            with open(args.cards_file) as f:
                wanted.update(line.strip() for line in f if line.strip())
        targets = [t for t in targets if (t.get("cardNumber") or "") in wanted]
        print(f"  Filter: {len(wanted)} cardNumbers requested → {len(targets)} targets")

    if args.limit:
        targets = targets[: args.limit]

    prog = load_progress()
    scanned = set(prog.get("scanned_boba", []))
    verified = already_verified_bobaids()

    pending: list[dict] = []
    for t in targets:
        bid = t.get("bobaId") or _boba_id(t)
        if not args.force and bid in scanned:
            continue
        if not args.force and _slug_for_file(bid) in verified:
            continue
        pending.append(t)

    print(f"  {len(targets)} targets · {len(pending)} pending · "
          f"{len(targets) - len(pending)} already done")

    if not pending:
        return

    session = make_session()

    # Open shared scan CSV (append, write header if new file)
    write_header = not SCAN_CSV.exists()
    out_fh = open(SCAN_CSV, "a", newline="", encoding="utf-8")
    w = csv.DictWriter(out_fh, fieldnames=SCAN_FIELDS, extrasaction="ignore")
    if write_header:
        w.writeheader()

    rows_written = 0
    cards_with_hits = 0
    cards_zero = 0
    failures = 0

    try:
        for i, target in enumerate(pending, 1):
            cn = (target.get("cardNumber") or "").strip()
            if not cn:
                continue
            bid = target.get("bobaId") or _boba_id(target)
            print(f"  [{i}/{len(pending)}] {cn:<14} {target.get('hero') or target.get('name') or ''}")

            try:
                listings = search_listings_for_card(session, cn)
            except Exception as e:
                sys.stderr.write(f"    error: {e}\n")
                failures += 1
                continue

            already_recorded = scan_csv_existing_listings_for_card(cn) if not args.force else set()

            kept = 0
            for listing in listings[: args.max_per_card]:
                lid = f"comc-{listing.item_id}"
                if lid in already_recorded:
                    continue
                # The image URL is fetched during the download phase to keep
                # scan-phase round trips minimal. Leave image_url blank here.
                w.writerow({
                    "bobaId":       bid,
                    "cardNumber":   cn,
                    "hero":         target.get("hero") or "",
                    "element":      target.get("element") or "",
                    "power":        target.get("power") or "",
                    "treatment":    target.get("treatment") or "",
                    "variation":    target.get("variation") or "",
                    "subSet":       target.get("subSet") or "",
                    "radishUrl":    target.get("radishUrl") or "",
                    "listing_id":   lid,
                    "ebay_url":     listing.detail_url,  # repurposed: COMC detail URL
                    "sold_date":    "",
                    "rank":         kept + 1,
                    "title":        f"{listing.year} BoBA {listing.set_slug.replace('_', ' ')} #{cn} {target.get('hero') or ''} [{listing.condition}]",
                    "image_url":    "",
                    "match_score":  "",
                    "source":       SOURCE_TAG,
                    "query_used":   f"/Cards,i100,={cn}",
                    "query_tier":   "comc-direct-cardnumber",
                })
                kept += 1
                rows_written += 1

            if kept > 0:
                cards_with_hits += 1
            else:
                cards_zero += 1
            scanned.add(bid)

            # Checkpoint every 25 cards
            if i % 25 == 0:
                out_fh.flush()
                prog["scanned_boba"] = sorted(scanned)
                prog["stats"] = {
                    "rows_written": rows_written,
                    "cards_with_hits": cards_with_hits,
                    "cards_zero": cards_zero,
                    "failures": failures,
                }
                save_progress(prog)

    finally:
        out_fh.close()
        prog["scanned_boba"] = sorted(scanned)
        prog["stats"] = {
            "rows_written": rows_written,
            "cards_with_hits": cards_with_hits,
            "cards_zero": cards_zero,
            "failures": failures,
        }
        save_progress(prog)

    print()
    print(f"  Scan complete:")
    print(f"    rows written:     {rows_written}")
    print(f"    cards with hits:  {cards_with_hits} of {len(pending)}")
    print(f"    cards with zero:  {cards_zero}")
    print(f"    fetch failures:   {failures}")


# ── Download phase ───────────────────────────────────────────────────────────
def cmd_download(args):
    if not SCAN_CSV.exists():
        print("  No scan CSV yet — run `scan` first.")
        return

    rows: list[dict] = []
    with SCAN_CSV.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if (r.get("source") or "").strip() != SOURCE_TAG:
                continue
            if not (r.get("listing_id") or "").strip():
                continue
            rows.append(r)

    if args.cards or args.cards_file:
        wanted = set()
        if args.cards:
            wanted.update(c.strip() for c in args.cards.split(",") if c.strip())
        if args.cards_file and os.path.exists(args.cards_file):
            with open(args.cards_file) as f:
                wanted.update(line.strip() for line in f if line.strip())
        rows = [r for r in rows if (r.get("cardNumber") or "").strip() in wanted]

    verified = already_verified_bobaids()
    if verified and not args.force:
        before = len(rows)
        rows = [r for r in rows
                if _slug_for_file(r.get("bobaId") or "") not in verified]
        print(f"  Skipping {before - len(rows)} rows whose bobaId is already verified.")

    if args.limit:
        rows = rows[: args.limit]

    print(f"  {len(rows)} COMC rows to process")
    if not rows:
        return

    session = make_session()
    saved = 0
    skipped_existing = 0
    failures = 0

    for i, row in enumerate(rows, 1):
        cn  = row["cardNumber"]
        bid = row.get("bobaId") or _boba_id({
            "cardNumber": cn,
            "hero": row.get("hero"),
            "treatment": row.get("treatment"),
            "variation": row.get("variation"),
        })
        slug = _slug_for_file(bid)
        lid  = row.get("listing_id") or ""
        item_id = lid.replace("comc-", "")
        dest = NEEDS_REVIEW / f"{slug}__{lid}__1.jpg"

        if dest.exists() and not args.force:
            skipped_existing += 1
            continue

        # Resolve image URL — prefer CSV's image_url if present (most won't have one
        # because we deferred the detail-page fetch to this phase).
        img_url = (row.get("image_url") or "").strip()
        if not img_url:
            detail_url = (row.get("ebay_url") or "").strip()
            if not detail_url:
                failures += 1
                continue
            try:
                listing_stub = ComcListing(
                    item_id=item_id, href="", detail_url=detail_url,
                    year="", set_slug="", card_number=cn, hero_slug="",
                    grading="", condition="", asking_price=None,
                )
                img_url = fetch_detail_image_url(session, listing_stub) or ""
            except Exception as e:
                sys.stderr.write(f"  detail-fetch error: {e}\n")
                failures += 1
                continue

        if not img_url:
            failures += 1
            continue

        # Download with image-shaped headers
        try:
            time.sleep(REQ_DELAY)
            r = session.get(img_url, timeout=TIMEOUT, headers=IMG_HEADERS,
                            stream=True)
        except requests.RequestException as e:
            sys.stderr.write(f"  download error: {e}\n")
            failures += 1
            continue

        if r.status_code != 200:
            sys.stderr.write(f"  HTTP {r.status_code} for {img_url}\n")
            failures += 1
            continue

        ctype = (r.headers.get("Content-Type") or "").lower()
        if "image" not in ctype:
            sys.stderr.write(f"  not an image: ctype={ctype} url={img_url}\n")
            failures += 1
            continue

        try:
            dest.write_bytes(r.content)
            saved += 1
            if (i % 20) == 0:
                print(f"  [{i}/{len(rows)}] {saved} saved · {skipped_existing} skipped · {failures} failed")
        except OSError as e:
            sys.stderr.write(f"  write error: {e}\n")
            failures += 1
            continue

    print()
    print(f"  Download complete:")
    print(f"    saved:            {saved}")
    print(f"    skipped existing: {skipped_existing}")
    print(f"    failures:         {failures}")


# ── Status ───────────────────────────────────────────────────────────────────
def cmd_status(_args):
    prog = load_progress()
    print(f"  Last run: {prog.get('last_run', 'never')}")
    print(f"  Cards scanned: {len(prog.get('scanned_boba', []))}")
    stats = prog.get("stats", {})
    if stats:
        for k, v in stats.items():
            print(f"    {k}: {v}")

    if SCAN_CSV.exists():
        comc_rows = 0
        comc_with_image = 0
        unique_cards = set()
        with SCAN_CSV.open(newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                if (r.get("source") or "") == SOURCE_TAG:
                    comc_rows += 1
                    unique_cards.add(r.get("cardNumber") or "")
                    if (r.get("image_url") or "").strip():
                        comc_with_image += 1
        print(f"  Scan CSV: {comc_rows} COMC rows across {len(unique_cards)} cards "
              f"({comc_with_image} with cached image_url)")

    if NEEDS_REVIEW.exists():
        comc_pending = sum(
            1 for p in NEEDS_REVIEW.iterdir()
            if p.is_file() and "__comc-" in p.name
        )
        print(f"  needs-review: {comc_pending} COMC images awaiting review")


def cmd_all(args):
    cmd_scan(args)
    cmd_download(args)


# ── CLI ──────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="COMC.com tier-3 image sourcer")
    sub = parser.add_subparsers(dest="cmd", required=True)

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--limit", type=int, help="cap on cards/rows processed")
    common.add_argument("--cards", help="comma-separated cardNumbers")
    common.add_argument("--cards-file", help="file with one cardNumber per line")
    common.add_argument("--force", action="store_true",
                        help="re-scan/re-download even if already recorded")

    sp = sub.add_parser("scan", parents=[common], help="find COMC listings for missing cards")
    sp.add_argument("--max-per-card", type=int, default=3,
                    help="keep at most N listings per card (default 3)")
    sp.set_defaults(func=cmd_scan)

    sp = sub.add_parser("download", parents=[common], help="pull images for scanned listings")
    sp.set_defaults(func=cmd_download)

    sp = sub.add_parser("all", parents=[common], help="scan + download")
    sp.add_argument("--max-per-card", type=int, default=3)
    sp.set_defaults(func=cmd_all)

    sp = sub.add_parser("status", help="progress + hit rate")
    sp.set_defaults(func=cmd_status)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
