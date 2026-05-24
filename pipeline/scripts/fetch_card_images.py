#!/usr/bin/env python3
"""
fetch_card_images.py — Phase 1 of CARD_AUDIT_PIPELINE.md

Downloads every catalog card's `imageFile` from R2 to a local cache
so subsequent OCR + visual passes can operate offline at full speed.

Usage:
    python3 pipeline/scripts/fetch_card_images.py \
        --catalog assets/data/cards.json \
        --cache   ~/.boba-card-audit/images \
        [--workers 8] [--limit N] [--force] [-v]

Behavior:
    - Skip files already on disk (idempotent), unless --force.
    - 3-attempt retry per file with exponential backoff
      (200ms → 600ms → 1500ms). Same pattern as the wall image
      loader; gentler on the R2 connection pool than a parallel-200
      burst.
    - Concurrency capped via ThreadPoolExecutor (--workers).
    - Progress reported every 100 files or every 10s, whichever
      comes first.

Output: ~/.boba-card-audit/images/{imageFile}, one file per card.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

# R2 CDN base — same constant as DECISIONS.md #008 / js/api.js / CDN.swift.
CDN_BASE = "https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev"

RETRY_DELAYS_S = [0.2, 0.6, 1.5]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--catalog", required=True,
                   help="Path to cards.json (e.g. assets/data/cards.json)")
    p.add_argument("--cache", required=True,
                   help="Destination dir (created if missing)")
    p.add_argument("--workers", type=int, default=8,
                   help="Parallel download workers (default 8)")
    p.add_argument("--limit", type=int, default=None,
                   help="Stop after fetching this many cards (debug)")
    p.add_argument("--force", action="store_true",
                   help="Re-download even if file already exists")
    p.add_argument("--types", nargs="+", default=None,
                   help="Restrict to these cardTypes (e.g. Hero Play)")
    p.add_argument("-v", "--verbose", action="store_true")
    return p.parse_args()


def cdn_url_for(card: dict) -> str:
    """
    Sealed Products live under /sealed/optimized/; everything else
    is under /full/. Matches the CDN.fullUrl helper in iOS / Android.
    """
    image_file = card.get("imageFile") or ""
    if card.get("cardType") == "Sealed Product":
        return f"{CDN_BASE}/sealed/optimized/{image_file}"
    return f"{CDN_BASE}/full/{image_file}"


def fetch_one(url: str, dest: Path) -> tuple[str, bool, str | None]:
    """
    Returns (url, ok, error_message). Writes bytes to dest atomically
    (temp file + rename) so a half-write doesn't leave a corrupt cache
    entry.
    """
    for attempt, delay in enumerate(RETRY_DELAYS_S + [None]):
        try:
            req = Request(url, headers={"User-Agent": "boba-card-audit/1.0"})
            with urlopen(req, timeout=30) as resp:
                if resp.status != 200:
                    raise HTTPError(url, resp.status, "non-200", resp.headers, None)
                data = resp.read()
            tmp = dest.with_suffix(dest.suffix + ".part")
            tmp.write_bytes(data)
            tmp.replace(dest)
            return (url, True, None)
        except (HTTPError, URLError, TimeoutError, OSError) as e:
            if delay is None:
                return (url, False, f"{type(e).__name__}: {e}")
            time.sleep(delay)
    return (url, False, "unreachable")


def main() -> int:
    args = parse_args()
    cache_dir = Path(os.path.expanduser(args.cache))
    cache_dir.mkdir(parents=True, exist_ok=True)

    with open(args.catalog) as f:
        cards = json.load(f)

    queue: list[tuple[str, Path]] = []
    for card in cards:
        if args.types and card.get("cardType") not in args.types:
            continue
        image_file = card.get("imageFile")
        if not image_file:
            continue
        dest = cache_dir / image_file
        if dest.exists() and not args.force:
            continue
        queue.append((cdn_url_for(card), dest))
        if args.limit and len(queue) >= args.limit:
            break

    print(f"[fetch] {len(queue)} cards to download "
          f"(cache: {cache_dir}, workers: {args.workers})", flush=True)
    if not queue:
        return 0

    started = time.time()
    done = 0
    failures: list[tuple[str, str]] = []
    last_progress = started

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(fetch_one, url, dest): (url, dest)
                   for url, dest in queue}
        for fut in as_completed(futures):
            url, ok, err = fut.result()
            done += 1
            if not ok:
                failures.append((url, err or "unknown"))
                if args.verbose:
                    print(f"[fetch] FAIL {url} — {err}", file=sys.stderr, flush=True)
            now = time.time()
            if done % 100 == 0 or (now - last_progress) >= 10:
                rate = done / max(0.1, now - started)
                eta = (len(queue) - done) / max(0.1, rate)
                print(f"[fetch] {done}/{len(queue)} "
                      f"({rate:.1f}/s, ETA {eta:.0f}s, failed {len(failures)})",
                      flush=True)
                last_progress = now

    elapsed = time.time() - started
    print(f"[fetch] done: {done - len(failures)} ok, "
          f"{len(failures)} failed, {elapsed:.1f}s total", flush=True)
    if failures:
        print(f"[fetch] first 10 failures:", file=sys.stderr)
        for url, err in failures[:10]:
            print(f"  {url} — {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
