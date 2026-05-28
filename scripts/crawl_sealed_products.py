#!/usr/bin/env python3
"""
crawl_sealed_products.py — fetch eBay active listings for each catalog Sealed
Product using HAND-CURATED search queries supplied by Ben (one query per SKU).

WHY SEPARATE FROM crawl_active_listings.py
-------------------------------------------
Sealed products are fundamentally per-SKU markets, not comparables (PRICING_
PLAYBOOK §6.6). A Griffey Hobby Box ≠ a Tecmo Hobby Box for pricing — each
Sealed has its own market, and the similarity model doesn't apply. The
similarity-comp search would also fail because Sealed cards carry no
treatment, no weapon, no hero — the only common axes are cardType, set,
variation, and printRun (none-vs-none); two random Sealed cards score sim=11
at best, and the model would average them onto one median, which is exactly
wrong.

The proxy's `/sealed` endpoint accepts a verbatim eBay search query, fetches
active listings, and pushes them to the tracker keyed on the supplied bobaId.
The builder then treats Sealed-cardType cards as a special path: if the card
has its own direct priced listings in the tracker, use the median of THOSE
as the estimate — no comparable search.

QUERIES
-------
Curated by Ben, one per Sealed SKU. Each query is the `_nkw=` term from an
eBay search URL that Ben verified produces real listings for that specific
Sealed product. 36 of 45 catalog Sealed entries are covered (the remaining 9
are National-pack variants and "Battle Trainer Kit Case" — easy to add when
queries are supplied).

USAGE
-----
    python3 scripts/crawl_sealed_products.py            # crawl all 36 SKUs
    python3 scripts/crawl_sealed_products.py --dry      # show mapping; don't fetch
"""

import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(REPO, "assets", "data", "cards.json")
PROXY = "https://boba-ebay-proxy.benwilkoff.workers.dev"

# Ben-curated (query, bobaId) mapping. Queries are passed verbatim to eBay
# Browse via the proxy's /sealed endpoint. Order matches the URL list Ben
# supplied 2026-05-28.
QUERIES = [
    ("2026 bo jackson battle arena Griffey Double Mega Box",          "SEALED-griffey-double-mega-box"),
    ("2025 bo jackson battle arena Alpha Update Blaster Box",         "SEALED-update-blaster-box"),
    ("2026 bo jackson battle arena Tecmo Double Mega Box",            "SEALED-tecmo-double-mega-box"),
    ("2026 bo jackson battle arena Griffey Blaster Box",              "SEALED-griffey-blaster-box"),
    ("2026 bo jackson battle arena Griffey Hobby Box",                "SEALED-griffey-hobby-box"),
    ("2025 bo jackson battle arena Alpha Update Collector Booster Box","SEALED-update-collector-booster-box"),
    ("2026 bo jackson battle arena Tecmo Hobby Box",                  "SEALED-tecmo-hobby-box"),
    ("2025 bo jackson battle arena Big League Chew (BLC) Blaster Box","SEALED-blc-blaster-box"),
    ("2025 bo jackson battle arena OKC World Champions Alt Art Box",  "SEALED-okc-world-champions-alt-art-box"),
    ("2025 bo jackson battle arena OKC World Champions Box",          "SEALED-okc-world-champions-box"),
    ("2024 bo jackson battle arena Alpha Edition Hobby Box",          "SEALED-alpha-hobby-box"),
    ("2025 bo jackson battle arena Alpha Update Jumbo Hobby Box",     "SEALED-update-jumbo-hobby-box"),
    ("2026 bo jackson battle arena Griffey Hobby Case",               "SEALED-griffey-hobby-case"),
    ("2025 bo jackson battle arena Alpha Update Hobby Box",           "SEALED-update-hobby-box"),
    ("2026 bo jackson battle arena Griffey Double Mega Case",         "SEALED-griffey-double-mega-case"),
    ("2025 bo jackson battle arena Alpha Update Collector Booster Case","SEALED-update-collector-booster-case"),
    ("2026 bo jackson battle arena Griffey Hobby Jumbo Box",          "SEALED-griffey-jumbo-hobby-box"),
    ("2026 bo jackson battle arena Griffey Release Day Blaster Box",  "SEALED-griffey-release-day-blaster"),
    ("2026 bo jackson battle arena Griffey Blaster Case",             "SEALED-griffey-blaster-case"),
    ("2024 bo jackson battle arena Alpha Edition Blaster Box",        "SEALED-alpha-blaster-box"),
    ("2025 bo jackson battle arena Philly World Champions Alt Art Box","SEALED-philly-world-champions-alt-art-box"),
    ("2024 bo jackson battle arena N'24 Starter Kit",                 "SEALED-national24-starter-kit"),
    ("2024 bo jackson battle arena Battle Trainer Kit",               "SEALED-alpha-battle-trainer-kit"),
    ("2025 bo jackson battle arena Alpha Blast Box",                  "SEALED-alpha-blast-box"),
    ("2025 bo jackson battle arena Philly World Champions Box",       "SEALED-philly-world-champions-box"),
    ("2024 bo jackson battle arena Alpha Edition Collector Booster Box","SEALED-alpha-collector-booster-box"),
    ("2024 bo jackson battle arena Alpha Edition Collector Booster Case","SEALED-alpha-collector-booster-case"),
    ("2024 bo jackson battle arena LA World Champions Box",           "SEALED-la-world-champions-box"),
    ("2024 bo jackson battle arena Alpha Edition Jumbo Hobby Box",    "SEALED-alpha-jumbo-hobby-box"),
    ("2025 bo jackson battle arena Alpha Update Blaster Case",        "SEALED-update-blaster-case"),
    ("2025 bo jackson battle arena Alpha Update Hobby Case",          "SEALED-update-hobby-case"),
    ("2025 bo jackson battle arena Alpha Update Jumbo Hobby Case",    "SEALED-update-jumbo-hobby-case"),
    ("2024 bo jackson battle arena Sandstorm Super Fan Box",          "SEALED-sandstorm-super-fan-box"),
    ("2024 bo jackson battle arena LA World Champions Alt Art Box",   "SEALED-la-world-champions-alt-art-box"),
    ("2024 bo jackson battle arena Alpha Edition Launch Day Bundle",  "SEALED-alpha-launch-day-bundle"),
    ("2024 bo jackson battle arena Alpha Edition Launch Day Bundle Case","SEALED-alpha-launch-day-bundle-case"),
]


def find_bobaid(catalog, bobaid_prefix):
    """Resolve a SEALED- prefix to a full catalog bobaId (the catalog suffixes
    include the full name + variation). Returns the first match or None."""
    for c in catalog:
        bid = c.get("bobaId") or ""
        if bid.startswith(bobaid_prefix + "-") or bid == bobaid_prefix:
            return bid
    return None


def crawl_one(query, bobaid, timeout):
    params = {"q": query, "bobaId": bobaid}
    url = f"{PROXY}/sealed?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": "boba-sealed-crawl/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true", help="print resolved mapping; don't call eBay")
    ap.add_argument("--delay", type=float, default=1.2)
    ap.add_argument("--timeout", type=float, default=15.0)
    args = ap.parse_args()

    catalog = json.load(open(CATALOG))
    resolved = []
    unresolved = []
    for query, bobaid_prefix in QUERIES:
        bid = find_bobaid(catalog, bobaid_prefix)
        if bid:
            resolved.append((query, bid))
        else:
            unresolved.append((query, bobaid_prefix))

    print(f"resolved {len(resolved)} / {len(QUERIES)} queries to catalog bobaIds")
    if unresolved:
        print(f"unresolved ({len(unresolved)}):")
        for q, p in unresolved:
            print(f"  prefix {p!r:60s} (query {q!r})")

    if args.dry:
        for q, bid in resolved[:10]:
            print(f"  q={q!r:75s} → {bid}")
        print("(dry — not crawling)")
        return

    total_count = 0
    with_listings = 0
    for i, (query, bid) in enumerate(resolved, 1):
        try:
            res = crawl_one(query, bid, args.timeout)
            n = int(res.get("count", 0))
            total_count += n
            with_listings += 1 if n > 0 else 0
            sample = res.get("sample") or []
            samp_str = " ; ".join(f"${s['price']:.0f}" for s in sample[:3])
            print(f"  [{i:>2}/{len(resolved)}] n={n:>3d} {bid[:40]:40s} | {samp_str}")
        except Exception as e:
            print(f"  [{i:>2}/{len(resolved)}] FAIL {bid[:40]:40s} | {e}", file=sys.stderr)
        time.sleep(args.delay)

    print(f"\nDONE: {with_listings}/{len(resolved)} SKUs got listings, {total_count} total listings pushed")


if __name__ == "__main__":
    main()
