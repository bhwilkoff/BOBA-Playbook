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
import re
import statistics
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from collections import defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(REPO, "assets", "data", "cards.json")
OUT = os.path.join(REPO, "assets", "data", "price-estimates.json")
TRACKER_DIR = os.path.join(REPO, "workers", "pricing-tracker")

SOLD_HAIRCUT = 0.82     # asking → estimated-sold (asks run ~10-25% above sold)
MIN_CARDS = 3           # confidence floor: a bucket needs this many OTHER priced cards
CONF_HIGH = 8
PROXY = "https://boba-ebay-proxy.benwilkoff.workers.dev"

# Weapon names that appear in Whatnot listing titles. Matched case-insensitive
# with word boundaries so "Steel" matches but "steelhead" doesn't. The catalog
# also has ALT/CYBER/NONE which rarely appear in titles; if a title lacks a
# weapon word the listing is dropped from the treatment-Whatnot aggregate
# (we'd otherwise dump it into a wrong bucket).
WEAPONS_IN_TITLE = ["FIRE", "ICE", "STEEL", "GLOW", "HEX", "GUM", "SUPER", "BRAWL"]
WEAPON_RE = re.compile(r"\b(" + "|".join(WEAPONS_IN_TITLE) + r")\b", re.IGNORECASE)


def parse_weapon_from_title(title):
    """Return the BoBA weapon string mentioned in a Whatnot/eBay listing
    title, or None when no weapon word is present (drop the listing then —
    putting it into a wrong bucket would be worse than missing it)."""
    if not title:
        return None
    m = WEAPON_RE.search(title)
    return m.group(1).upper() if m else None


def fetch_whatnot_aggregate(treatment, timeout=12):
    """Query the eBay proxy's Whatnot endpoint with just the treatment name
    (no per-card filter) and return [(weapon, price), …] for listings whose
    title cleanly identifies a weapon. The proxy's anti-bot already passes;
    its 12-min edge cache amortizes the scrape across multiple build runs."""
    url = f"{PROXY}/whatnot/products?{urllib.parse.urlencode({'query': treatment})}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "boba-baseline-builder/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data = json.loads(r.read().decode())
    except Exception as e:
        print(f"  ! whatnot fetch failed for {treatment!r}: {e}", file=sys.stderr)
        return []
    out = []
    for li in (data.get("listings") or []):
        price = li.get("price")
        if not (isinstance(price, (int, float)) and price > 0):
            continue
        w = parse_weapon_from_title(li.get("title") or "")
        if w:
            out.append((w, float(price)))
    return out


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

    # ── Whatnot treatment-level augmentation ──────────────────────────────
    # Many catalog treatments (mainstream battlefoils, color blasts, Inspired
    # Ink series) trade more on Whatnot than eBay. The proxy's per-card
    # matchesCard filter is necessarily strict — it requires cardNumber+weapon
    # in the listing title — but Whatnot titles rarely include catalog
    # cardNumber prefixes (GLBF, RAD, BLBF). So we query Whatnot ONCE per
    # treatment (treatment-level, no per-card filter), parse the weapon out
    # of each title, and inject those prices into the L3 (treatment × weapon)
    # buckets. These are treatment-level signals, not per-card, so they carry
    # a sentinel bobaId that never matches the self-exclusion check.
    # Cost: zero eBay quota. Whatnot scrapes cached 12 min by the proxy.
    print("\nWhatnot treatment-level augmentation:")
    distinct_treatments = sorted({(c.get("treatment") or "") for c in cards if c.get("treatment")})
    # Only query treatments where AT LEAST one (treatment × weapon) bucket
    # is under-filled — no point hammering Whatnot for treatments already
    # covered by per-card data.
    treatments_to_query = []
    for t_str in distinct_treatments:
        fam = treatment_family(t_str)
        # Does any weapon in this treatment-family have under-MIN_CARDS data?
        weapons_used = {(c.get("element") or "NONE") for c in cards
                        if c.get("bobaId") and (c.get("treatment") or "") == t_str}
        if any(len(buckets["l3"][f"{fam}|{w}"]) < MIN_CARDS for w in weapons_used):
            treatments_to_query.append(t_str)
    print(f"  under-filled treatments to query: {len(treatments_to_query)}")
    WN_SENTINEL = "_whatnot_treatment_aggregate_"
    wn_added = defaultdict(int)
    for i, t_str in enumerate(treatments_to_query, 1):
        items = fetch_whatnot_aggregate(t_str)
        if items:
            fam = treatment_family(t_str)
            for weapon, price in items:
                l3_key = f"{fam}|{weapon}"
                # Asking → estimated-sold via SOLD_HAIRCUT, same rule as
                # per-card asks. Sentinel bobaId so self-exclusion is a no-op.
                buckets["l3"][l3_key].append((WN_SENTINEL, price * SOLD_HAIRCUT))
                wn_added[l3_key] += 1
        if i % 10 == 0:
            print(f"  ... {i}/{len(treatments_to_query)} treatments queried")
        time.sleep(0.6)  # gentle pacing — proxy caches per-query, this is per-treatment
    print(f"  Whatnot prices added across {len(wn_added)} (treatment×weapon) buckets: "
          f"{sum(wn_added.values())} prices total")

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
