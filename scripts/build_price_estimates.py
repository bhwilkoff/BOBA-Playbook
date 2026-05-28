#!/usr/bin/env python3
"""
build_price_estimates.py — turn the price data we collect ourselves into a
rough estimate for every card whose RARITY CLASS has data, written as a
static artifact the clients read (PRICING_PLAYBOOK §6 · DECISIONS.md #058).

WHY OFFLINE (not the estimator Worker)
--------------------------------------
The catalog is 17,974 cards. Computing a comparable estimate per card means
scanning the catalog + reading comp prices — fine offline, but a Cloudflare
*free-plan* Worker caps at 50 subrequests/invocation, so a cron can't grind
the catalog (the same wall that pushed the tracker to a push model). So the
heavy lifting runs HERE (local, via the daily macOS cron — see
`project_pipeline_architecture`), exactly like the catalog pipeline: offline
compute → static JSON → clients read. No Worker grind, no KV write limits,
no per-request catalog load.

THE MODEL — rarity-first, asks-haircut, confidence-floored
----------------------------------------------------------
Price tracks RARITY, not hero (PRICING_PLAYBOOK §6.2). For each card we find
the TIGHTEST rarity bucket that has enough *other* priced cards and take the
median, walking looser only as needed:

    L1  treatment-family × weapon × power-tier × card-type   (tightest)
    L2  treatment-family × weapon × power-tier
    L3  treatment-family × weapon
    L4  treatment-family
    L5  weapon                                               (rarity-tier proxy)

A card's own price (when it has listings) is shown directly as "Listed Range"
on the client and is NOT what this estimate is for — the estimate is the
comp-less fallback, so we EXCLUDE the card itself from its bucket.

**Provenance honesty (#058):**
- Sold comps (inferred + community) are preferred per card; asking prices are
  used only with a SOLD_HAIRCUT (asks run ~10-25% above transacted) and the
  artifact records which kind backed each bucket.
- CONFIDENCE FLOOR: a bucket must have >= MIN_CARDS priced members or we DON'T
  emit an estimate for cards relying on it. No global-average fallback — a
  card whose entire rarity class is unknown honestly shows "no estimate yet"
  (better than a fabricated number). Coverage grows as the crawl fills data.

OUTPUT: assets/data/price-estimates.json
    { "generatedAt", "soldHaircut", "minCards",
      "estimates": { "<bobaId>": {"low","mid","high","n","level","basis"} } }

USAGE
-----
    python3 scripts/build_price_estimates.py            # pull D1 live + build
    python3 scripts/build_price_estimates.py --dry      # print coverage, don't write
"""

import argparse
import json
import os
import statistics
import subprocess
import sys
from collections import defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(REPO, "assets", "data", "cards.json")
OUT = os.path.join(REPO, "assets", "data", "price-estimates.json")
TRACKER_DIR = os.path.join(REPO, "workers", "pricing-tracker")

SOLD_HAIRCUT = 0.82     # asking → estimated-sold (asks run ~10-25% above sold)
MIN_CARDS = 3           # confidence floor: a bucket needs this many OTHER priced cards
CONF_HIGH = 8


def treatment_family(t):
    """Use the treatment STRING itself as the family key (normalized).

    The catalog has 59 distinct treatments; each is a real rarity class
    (Pink Blast ≠ Base Set ≠ Silver Battlefoil — different runs, different
    prices, per PRICING_PLAYBOOK §6.4). Earlier this function collapsed many
    of them onto a handful of keys ("base", "battlefoil_color", etc.), which
    dragged the bucket median wrong (mixing Base Set commons with Blast/Hot
    Dog/Cyber chase variants) and hid genuine misses. One treatment → one
    family is the honest design. Lockstep with crawl_active_listings.py."""
    if not t:
        return "none"
    return (t.lower()
              .replace("'", "")
              .replace(" & ", "_and_")
              .replace("&", "and")
              .replace(" ", "_"))


def power_tier(p):
    if p is None:
        return "na"
    return "lo" if p <= 25 else "mid" if p <= 60 else "hi" if p <= 100 else "elite"


def pull_tracker_prices():
    """Return {bobaId: (median_price, kind)} where kind is 'sold' or 'ask'.
    Sold (inferred + community-confidence) preferred; else active asking."""
    def d1(sql):
        out = subprocess.run(
            ["npx", "wrangler", "d1", "execute", "boba-pricing", "--remote", "--json", "--command", sql],
            cwd=TRACKER_DIR, capture_output=True, text=True, timeout=180,
        )
        if out.returncode != 0:
            print(out.stderr[-500:], file=sys.stderr)
            raise RuntimeError("wrangler d1 query failed")
        return json.loads(out.stdout)[0]["results"]

    sold = defaultdict(list)
    for r in d1("SELECT boba_id, sold_price_usd AS p FROM listings "
                "WHERE inferred_sold=1 AND sold_confidence>=0.55 AND sold_price_usd>0;"):
        sold[r["boba_id"]].append(r["p"])
    ask = defaultdict(list)
    for r in d1("SELECT boba_id, price_usd AS p FROM listings "
                "WHERE vanished_at IS NULL AND price_usd>0;"):
        ask[r["boba_id"]].append(r["p"])

    prices = {}
    for bid, v in sold.items():
        prices[bid] = (statistics.median(v), "sold")
    for bid, v in ask.items():
        if bid not in prices:                       # sold wins when both exist
            prices[bid] = (statistics.median(v) * SOLD_HAIRCUT, "ask")
    return prices


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true", help="print coverage; don't write the artifact")
    args = ap.parse_args()

    cards = json.load(open(CATALOG))
    prices = pull_tracker_prices()
    print(f"catalog={len(cards)} priced_cards={len(prices)} "
          f"(sold={sum(1 for _,k in prices.values() if k=='sold')} "
          f"ask={sum(1 for _,k in prices.values() if k=='ask')})")

    # Index priced cards into each bucket level (store the price + bobaId so we
    # can exclude a card from its own bucket). Floor at L3 = treatment-family ×
    # weapon: the loosest bucket that is still a real RARITY CLASS. We do NOT
    # emit weapon-only (a weapon spans base commons → serialized chase) or
    # family-only (inspired-ink is serialized BY weapon — /5 Hex ≫ /50 Ice)
    # estimates: those collapse wildly different cards onto one median and
    # violate provenance honesty (#058). Comp-less rarity classes honestly show
    # no estimate until the crawl fills their bucket.
    levels = ["l1", "l2", "l3"]
    buckets = {lv: defaultdict(list) for lv in levels}

    def keys_for(c):
        fam = treatment_family(c.get("treatment"))
        el = c.get("element") or "NONE"
        pt = power_tier(c.get("power"))
        ct = c.get("cardType") or "na"
        return {
            "l1": f"{fam}|{el}|{pt}|{ct}",
            "l2": f"{fam}|{el}|{pt}",
            "l3": f"{fam}|{el}",
        }

    for c in cards:
        bid = c.get("bobaId")
        if bid in prices:
            price = prices[bid][0]
            for lv, k in keys_for(c).items():
                buckets[lv][k].append((bid, price))

    LEVEL_BASIS = {
        "l1": "treatment + weapon + power + type",
        "l2": "treatment + weapon + power",
        "l3": "treatment + weapon",
    }

    estimates = {}
    cov = defaultdict(int)
    for c in cards:
        bid = c.get("bobaId")
        if not bid:
            continue
        ks = keys_for(c)
        for lv in levels:
            members = [p for (mid, p) in buckets[lv][ks[lv]] if mid != bid]  # exclude self
            if len(members) >= MIN_CARDS:
                members.sort()
                n = len(members)
                # Robust range: report the interquartile band (p25 / median /
                # p75), NOT min/max — eBay asks include wild outliers (a single
                # mispriced or slabbed listing would otherwise blow the range to
                # $2–$152). The median is the headline; p25–p75 is an honest band.
                def pct(q):
                    return members[min(n - 1, int(q * (n - 1) + 0.5))]
                estimates[bid] = {
                    "low": round(pct(0.25), 2),
                    "mid": round(pct(0.50), 2),
                    "high": round(pct(0.75), 2),
                    "n": n,
                    "level": lv,
                    "basis": LEVEL_BASIS[lv],
                    # No "high" confidence while estimates are ASK-derived (no
                    # sold comps back them yet, #058). Tight rarity class with
                    # many comps = "med"; everything looser/sparser = "low".
                    "conf": "med" if (lv in ("l1", "l2") and n >= CONF_HIGH) else "low",
                }
                cov[lv] += 1
                break

    print(f"estimates produced: {len(estimates)} / {len(cards)} cards "
          f"({100*len(estimates)//max(1,len(cards))}% coverage)")
    for lv in levels:
        print(f"  {lv} ({LEVEL_BASIS[lv]}): {cov[lv]} cards")

    if args.dry:
        print("(dry run — not writing)")
        return

    import datetime
    payload = {
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "soldHaircut": SOLD_HAIRCUT,
        "minCards": MIN_CARDS,
        "method": "rarity_bucket_v1",
        "estimates": estimates,
    }
    json.dump(payload, open(OUT, "w"), separators=(",", ":"))
    size_kb = os.path.getsize(OUT) // 1024
    print(f"wrote {OUT} ({size_kb} KB)")


if __name__ == "__main__":
    main()
