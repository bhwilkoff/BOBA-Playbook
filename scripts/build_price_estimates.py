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

# Weapon names that appear in listing titles. Matched case-insensitive with
# word boundaries so "Steel" matches but "steelhead" doesn't. ALT/CYBER/NONE
# rarely appear in titles; titles lacking a recognizable weapon are skipped
# from the treatment-level fallback (per-card cardNumber match is tried first
# below — it's far more precise).
WEAPONS_IN_TITLE = ["FIRE", "ICE", "STEEL", "GLOW", "HEX", "GUM", "SUPER", "BRAWL"]
WEAPON_RE = re.compile(r"\b(" + "|".join(WEAPONS_IN_TITLE) + r")\b", re.IGNORECASE)

# Catalog cardNumbers look like "BF-272", "GLBF-365", "P-8", "GGLBF-116",
# "ABF-1", "RAD-208" — alphabetic prefix + optional letter + digits. The
# leading delimiter is "#", whitespace, or start-of-string.
CARDNUMBER_RE = re.compile(r"(?:^|[#\s])([A-Z]{1,8}-[A-Z]?\d{1,4})\b")


def parse_weapon_from_title(title):
    if not title:
        return None
    m = WEAPON_RE.search(title)
    return m.group(1).upper() if m else None


def parse_cardnumber_from_title(title):
    """Return the first BoBA cardNumber found in a listing title (e.g.,
    "BLBF-15"), or None. Used by the Whatnot augmentation to resolve listings
    to specific catalog cards when the seller bothered to include the
    cardNumber — far more precise than weapon-only treatment aggregates."""
    if not title:
        return None
    m = CARDNUMBER_RE.search(title.upper())
    return m.group(1) if m else None


def fetch_whatnot_listings(treatment, timeout=12):
    """Hit the eBay proxy's Whatnot endpoint with just a treatment name (no
    per-card filter) and return the raw listings list. The proxy's anti-bot
    egress already passes; its 12-min edge cache amortizes scrapes across
    build runs. Caller does the title parsing (cardNumber → catalog, else
    weapon word → treatment-level aggregate)."""
    url = f"{PROXY}/whatnot/products?{urllib.parse.urlencode({'query': treatment})}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "boba-baseline-builder/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data = json.loads(r.read().decode())
    except Exception as e:
        print(f"  ! whatnot fetch failed for {treatment!r}: {e}", file=sys.stderr)
        return []
    return [li for li in (data.get("listings") or [])
            if isinstance(li.get("price"), (int, float)) and li["price"] > 0]


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

    # ── Whatnot augmentation ─────────────────────────────────────────────
    # Many catalog treatments (mainstream battlefoils, color blasts, Inspired
    # Ink series) trade more on Whatnot than eBay. Two-tier resolution per
    # listing — most specific first:
    #
    #   (A) If the title contains a catalog cardNumber (e.g., "BLBF-15",
    #       "GLBF-365", "RAD-208"), look it up in the catalog and treat it as
    #       a per-card price feeding ALL bucket levels (L1/L2/L3) for that
    #       specific card. Resolution gates on the queried treatment-family
    #       to disambiguate cardNumbers that recur across reissues; when
    #       multiple weapons share the cardNumber+treatment, the title's
    #       weapon word disambiguates.
    #   (B) If only a weapon word is parseable, fall back to a treatment ×
    #       weapon level aggregate (L3 bucket), with a sentinel bobaId so
    #       the self-exclusion check is a no-op.
    #
    # Asks × SOLD_HAIRCUT for both. Zero eBay quota; proxy caches scrapes
    # 12 min. Per-card matches (A) are FAR more precise than treatment
    # aggregates and feed the tightest L1 bucket — usually the dominant
    # contributor when Whatnot listings include cardNumber prefixes.
    print("\nWhatnot augmentation:")

    # Build a lookup: (cardNumber-uppercase, treatment-family) → [card, …].
    cards_by_cn_fam = defaultdict(list)
    for c in cards:
        cn = c.get("cardNumber")
        t = c.get("treatment")
        if cn and t:
            cards_by_cn_fam[(cn.upper(), treatment_family(t))].append(c)

    bid_to_card = {c["bobaId"]: c for c in cards if c.get("bobaId")}

    distinct_treatments = sorted({(c.get("treatment") or "") for c in cards if c.get("treatment")})
    treatments_to_query = []
    for t_str in distinct_treatments:
        fam = treatment_family(t_str)
        weapons_used = {(c.get("element") or "NONE") for c in cards
                        if c.get("bobaId") and (c.get("treatment") or "") == t_str}
        if any(len(buckets["l3"][f"{fam}|{w}"]) < MIN_CARDS for w in weapons_used):
            treatments_to_query.append(t_str)
    print(f"  under-filled treatments to query: {len(treatments_to_query)}")

    WN_SENTINEL = "_whatnot_treatment_aggregate_"
    matched_by_card = 0
    matched_by_treatment = 0
    dropped_unparseable = 0

    for i, t_str in enumerate(treatments_to_query, 1):
        items = fetch_whatnot_listings(t_str)
        fam = treatment_family(t_str)
        for li in items:
            price = float(li["price"])
            title = li.get("title") or ""
            # (A) cardNumber path — most precise.
            cn = parse_cardnumber_from_title(title)
            cands = cards_by_cn_fam.get((cn, fam), []) if cn else []
            chosen = None
            if len(cands) == 1:
                chosen = cands[0]
            elif len(cands) > 1:
                # Same cardNumber + treatment across multiple weapons (FIRE/GLOW
                # variant pairs, #057). Disambiguate from the title's weapon word.
                w_in_title = parse_weapon_from_title(title)
                if w_in_title:
                    for cand in cands:
                        if (cand.get("element") or "").upper() == w_in_title:
                            chosen = cand
                            break
            if chosen and chosen.get("bobaId"):
                bid = chosen["bobaId"]
                priced = price * SOLD_HAIRCUT
                for lv, k in keys_for(chosen).items():
                    buckets[lv][k].append((bid, priced))
                matched_by_card += 1
                continue
            # (B) weapon-only fallback → L3 aggregate.
            w = parse_weapon_from_title(title)
            if w:
                buckets["l3"][f"{fam}|{w}"].append((WN_SENTINEL, price * SOLD_HAIRCUT))
                matched_by_treatment += 1
            else:
                dropped_unparseable += 1
        if i % 10 == 0:
            print(f"  ... {i}/{len(treatments_to_query)} treatments queried")
        time.sleep(0.6)  # gentle pacing — proxy caches per-query, this is per-treatment
    print(f"  Whatnot listings → per-card matches: {matched_by_card}, "
          f"treatment-level aggregates: {matched_by_treatment}, "
          f"dropped (no cardNumber/weapon): {dropped_unparseable}")

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
