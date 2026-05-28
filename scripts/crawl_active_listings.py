#!/usr/bin/env python3
"""
crawl_active_listings.py — seed the pricing-tracker with active-listing
data across the WHOLE catalog, so the estimator has representative comps
to work from (PRICING_PLAYBOOK §3/§6 · DECISIONS.md #058).

WHY THIS EXISTS
---------------
The push model (proxy → tracker /ingest on every card view + Collection
refresh) only collects price data for cards users actually open. As of
2026-05-27 that was 60 cards — 59 of them "base" treatment, 45 FIRE —
nowhere near enough to anchor a per-card rarity estimate (most rarity
buckets empty → estimates collapse to a meaningless global average). The
estimator's comparability logic is ready; it just needs data.

This script walks the catalog through the *same* eBay proxy the app uses
(`GET /?cardNumber=&hero=&set=&element=&bobaId=`). The proxy fetches eBay
active listings and — via the existing push model (`pushIngest`,
ctx.waitUntil) — records them into the tracker D1 keyed on bobaId. No new
infrastructure: we just exercise the proxy across the catalog instead of
waiting for organic views.

DESIGN
------
- **Stratified order.** Cards are round-robined across
  (treatment-family × weapon) buckets so coverage fills EVENLY — the
  estimator needs a few priced cards in each rarity class, not 17k base
  FIRE cards first.
- **Resumable.** A cursor file records crawled bobaIds; re-runs skip them.
  Safe to wire into the existing daily macOS cron (see
  `project_pipeline_architecture`).
- **Quota-safe.** eBay Browse is ~5000 calls/day; default --limit 800
  leaves headroom for live user traffic. SEQUENTIAL with a delay — never
  parallel (the proxy + eBay rate-limit, and parallel-same-token bursts
  have burned us before).
- **Read-only on the catalog.** Never writes cards.json. The only side
  effect is tracker D1 rows via the proxy's push.

USAGE
-----
    python3 scripts/crawl_active_listings.py --limit 800
    python3 scripts/crawl_active_listings.py --limit 2000 --delay 1.0
    python3 scripts/crawl_active_listings.py --reset        # clear cursor
"""

import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from collections import defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(REPO, "assets", "data", "cards.json")
# One cursor per --source so eBay and Whatnot don't share state — different
# marketplaces have different inventory, so what's "covered" on one isn't on
# the other. Both cursors live in scripts/ (gitignored).
CURSOR_BY_SOURCE = {
    "ebay":    os.path.join(REPO, "scripts", ".active_crawl_cursor.json"),
    "whatnot": os.path.join(REPO, "scripts", ".active_crawl_cursor_whatnot.json"),
}
PROXY = "https://boba-ebay-proxy.benwilkoff.workers.dev"


def treatment_family(t):
    """Lockstep with scripts/build_price_estimates.py::treatment_family —
    one treatment string → one family key. The catalog has 59 distinct
    treatments (Pink Blast, Base Set, Silver Battlefoil, etc.); each is a
    real rarity class so the stratifier should give each a fair share."""
    if not t:
        return "none"
    return (t.lower()
              .replace("'", "")
              .replace(" & ", "_and_")
              .replace("&", "and")
              .replace(" ", "_"))


def load_cursor(source):
    path = CURSOR_BY_SOURCE[source]
    if os.path.exists(path):
        try:
            return set(json.load(open(path)).get("done", []))
        except Exception:
            return set()
    return set()


def save_cursor(done, source):
    json.dump({"done": sorted(done)}, open(CURSOR_BY_SOURCE[source], "w"))


def stratified_order(cards, done):
    """Round-robin across (treatment-family, weapon) buckets so coverage
    fills evenly. Within a bucket, leave catalog order (cards with art /
    lower numbers tend to be the ones people research)."""
    buckets = defaultdict(list)
    for c in cards:
        bid = c.get("bobaId")
        if not bid or bid in done:
            continue
        if not c.get("cardNumber"):
            continue
        key = (treatment_family(c.get("treatment")), c.get("element") or "NONE")
        buckets[key].append(c)
    order = []
    keys = list(buckets.keys())
    idx = {k: 0 for k in keys}
    remaining = True
    while remaining:
        remaining = False
        for k in keys:
            i = idx[k]
            if i < len(buckets[k]):
                order.append(buckets[k][i])
                idx[k] += 1
                remaining = True
    return order


def crawl_one(card, timeout):
    """Hit eBay via the proxy root — the proxy fetches active listings AND
    push-ingests them into the tracker (DECISIONS.md #058). Counts toward
    eBay's daily Browse quota (~5000/day)."""
    params = {
        "cardNumber": card.get("cardNumber", ""),
        "hero": card.get("hero", "") or "",
        "set": card.get("set", "") or "",
        "element": card.get("element", "") or "",
        "days": "90",
        "bobaId": card.get("bobaId", ""),
    }
    url = f"{PROXY}/?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": "boba-active-crawl/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.loads(r.read().decode())
    active = (data.get("active") or {}).get("count", 0) if data.get("active") else 0
    return active


def crawl_one_whatnot(card, timeout):
    """Hit Whatnot via the proxy — the proxy scrapes Whatnot listings, matches
    by (cardNumber, weapon, treatment, power), and push-ingests matched ones
    into the tracker. Costs ZERO eBay quota — the right channel for treatments
    that trade on Whatnot more than eBay (mainstream battlefoils, color blasts,
    Inspired Ink series). Returns the matchesCard count."""
    params = {
        "query":      card.get("hero", "") or "",
        "cardNumber": card.get("cardNumber", ""),
        "weapon":     card.get("element", "") or "",
        "treatment":  card.get("treatment", "") or "",
        "bobaId":     card.get("bobaId", ""),
    }
    if card.get("power") is not None:
        params["power"] = str(card["power"])
    url = f"{PROXY}/whatnot/products?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": "boba-active-crawl/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.loads(r.read().decode())
    listings = data.get("listings") or []
    return sum(1 for l in listings if l.get("matchesCard"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=800, help="max cards this run (eBay-quota guard)")
    ap.add_argument("--delay", type=float, default=1.2, help="seconds between calls (rate-limit guard)")
    ap.add_argument("--timeout", type=float, default=12.0)
    ap.add_argument("--treatments", default="",
                    help="CSV of exact treatment strings to focus this run on; "
                         "all other treatments are skipped. Used to fill empty "
                         "rarity buckets identified by the builder's coverage audit.")
    ap.add_argument("--source", choices=("ebay", "whatnot"), default="ebay",
                    help="which marketplace to crawl per card. ebay (default) "
                         "burns eBay Browse quota; whatnot costs zero eBay quota "
                         "and is the right channel for treatments that trade more "
                         "on Whatnot than eBay (mainstream battlefoils, blasts, "
                         "Inspired Ink). Uses a separate cursor per source.")
    ap.add_argument("--reset", action="store_true", help="clear the resume cursor and exit")
    args = ap.parse_args()

    if args.reset:
        path = CURSOR_BY_SOURCE[args.source]
        if os.path.exists(path):
            os.remove(path)
        print(f"{args.source} cursor cleared")
        return

    cards = json.load(open(CATALOG))
    done = load_cursor(args.source)
    crawl_fn = crawl_one_whatnot if args.source == "whatnot" else crawl_one
    print(f"source={args.source}")
    # Targeted-fill mode: restrict the queue to cards in specific treatments
    # (e.g., to fill rarity-buckets the coverage audit flagged as empty).
    if args.treatments:
        focus = {t.strip() for t in args.treatments.split(",") if t.strip()}
        cards_for_order = [c for c in cards if (c.get("treatment") or "") in focus]
        print(f"targeted treatments ({len(focus)}): {sorted(focus)}")
    else:
        cards_for_order = cards
    order = stratified_order(cards_for_order, done)
    print(f"catalog={len(cards)} already_crawled={len(done)} queued={len(order)} limit={args.limit}")

    crawled = 0
    with_listings = 0
    for card in order:
        if crawled >= args.limit:
            break
        bid = card["bobaId"]
        try:
            n = crawl_fn(card, args.timeout)
            with_listings += 1 if n > 0 else 0
            done.add(bid)
            crawled += 1
            if crawled % 25 == 0:
                save_cursor(done, args.source)
                print(f"  {crawled}/{args.limit}  listings_found={with_listings}  last={bid[:40]} (n={n})")
        except KeyboardInterrupt:
            break
        except Exception as e:
            # A single-card failure (timeout / proxy hiccup) must not abort
            # the run — mark done so we don't retry-loop a bad card forever.
            done.add(bid)
            crawled += 1
            print(f"  skip {bid[:40]}: {e}", file=sys.stderr)
        time.sleep(args.delay)

    save_cursor(done, args.source)
    print(f"DONE this run: source={args.source} crawled={crawled} with_listings={with_listings} total_done={len(done)}")


if __name__ == "__main__":
    main()
