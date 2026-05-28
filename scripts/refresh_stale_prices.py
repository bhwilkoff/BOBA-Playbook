#!/usr/bin/env python3
"""
refresh_stale_prices.py — re-crawl cards whose tracker data is going stale.

Without this loop, the estimator's input data ages: a card last viewed three
weeks ago still has 3-week-old listings driving its bucket median, and any
sales that happened in between never get vanish-inferred because we never
took a second snapshot.

For each card whose newest tracker observation is older than --stale-days,
re-fetch via the eBay proxy (or Whatnot, on a --source flag). The proxy's
push model re-ingests into the tracker; price-trajectory snapshots and
vanish-inference happen automatically on the tracker side (PRICING_PLAYBOOK
§6.6). Quota-safe — --limit caps the per-run eBay Browse spend.

Cadence: this script is intended for daily execution alongside the catalog
crawl (see scripts/crawl_active_listings.py). It complements organic user
views — popular cards refresh via the push model on every view; the long
tail refreshes here.

USAGE
-----
    python3 scripts/refresh_stale_prices.py                       # default: 7-day stale, 500 cards
    python3 scripts/refresh_stale_prices.py --stale-days 14
    python3 scripts/refresh_stale_prices.py --limit 1000          # bigger refresh
    python3 scripts/refresh_stale_prices.py --source whatnot      # zero eBay quota
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(REPO, "assets", "data", "cards.json")
TRACKER_DIR = os.path.join(REPO, "workers", "pricing-tracker")
PROXY = "https://boba-ebay-proxy.benwilkoff.workers.dev"


def stale_bobaids(days):
    """Return [(bobaId, newest_iso)] for cards whose most-recent tracker
    observation is older than `days`. Oldest first (so we refresh the most
    stale cards first when --limit is hit before the queue empties)."""
    sql = (
        "SELECT boba_id, MAX(last_seen) AS newest "
        "FROM listings "
        "GROUP BY boba_id "
        f"HAVING julianday('now') - julianday(newest) > {int(days)} "
        "ORDER BY newest ASC;"
    )
    out = subprocess.run(
        ["npx", "wrangler", "d1", "execute", "boba-pricing", "--remote", "--json", "--command", sql],
        cwd=TRACKER_DIR, capture_output=True, text=True, timeout=180,
    )
    if out.returncode != 0:
        print(out.stderr[-500:], file=sys.stderr)
        raise RuntimeError("wrangler d1 query failed")
    rows = json.loads(out.stdout)[0]["results"]
    return [(r["boba_id"], r["newest"]) for r in rows]


def crawl_one_ebay(card, timeout):
    params = {
        "cardNumber": card.get("cardNumber") or "",
        "hero": card.get("hero") or "",
        "set": card.get("set") or "",
        "element": card.get("element") or "",
        "days": "90",
        "bobaId": card.get("bobaId") or "",
    }
    url = f"{PROXY}/?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": "boba-stale-refresh/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.loads(r.read().decode())
    return (data.get("active") or {}).get("count", 0) if data.get("active") else 0


def crawl_one_whatnot(card, timeout):
    params = {
        "query": card.get("hero") or "",
        "cardNumber": card.get("cardNumber") or "",
        "weapon": card.get("element") or "",
        "treatment": card.get("treatment") or "",
        "bobaId": card.get("bobaId") or "",
    }
    if card.get("power") is not None:
        params["power"] = str(card["power"])
    url = f"{PROXY}/whatnot/products?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": "boba-stale-refresh/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.loads(r.read().decode())
    return sum(1 for l in (data.get("listings") or []) if l.get("matchesCard"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stale-days", type=int, default=7,
                    help="cards with their newest tracker observation older than this many days are refreshed (default 7)")
    ap.add_argument("--limit", type=int, default=500,
                    help="quota guard — max cards refreshed this run (default 500)")
    ap.add_argument("--delay", type=float, default=1.0)
    ap.add_argument("--timeout", type=float, default=12.0)
    ap.add_argument("--source", choices=("ebay", "whatnot"), default="ebay")
    args = ap.parse_args()

    queue = stale_bobaids(args.stale_days)
    cards = {c["bobaId"]: c for c in json.load(open(CATALOG)) if c.get("bobaId")}
    print(f"stale (>{args.stale_days}d) cards in tracker: {len(queue)} | limit: {args.limit} | source: {args.source}")

    crawl_fn = crawl_one_whatnot if args.source == "whatnot" else crawl_one_ebay

    crawled = 0
    with_listings = 0
    for bid, newest in queue:
        if crawled >= args.limit:
            break
        card = cards.get(bid)
        if not card:
            # Catalog evolved past this bobaId — skip silently (it won't get
            # an estimate either way).
            continue
        try:
            n = crawl_fn(card, args.timeout)
            with_listings += 1 if n > 0 else 0
            crawled += 1
            if crawled % 25 == 0:
                age_days = "?"
                try:
                    import datetime
                    age_days = int((datetime.datetime.now(datetime.timezone.utc)
                                   - datetime.datetime.fromisoformat(newest.replace("Z", "+00:00"))).total_seconds() / 86400)
                except Exception:
                    pass
                print(f"  {crawled}/{args.limit}  with_listings={with_listings}  oldest_age={age_days}d")
        except KeyboardInterrupt:
            break
        except Exception as e:
            crawled += 1
            print(f"  skip {bid[:40]}: {e}", file=sys.stderr)
        time.sleep(args.delay)

    print(f"DONE this run: source={args.source} crawled={crawled} with_listings={with_listings}")


if __name__ == "__main__":
    main()
