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
MIN_CARDS = 3           # need at least this many comps for any estimate
CONF_HIGH = 8
PROXY = "https://boba-ebay-proxy.benwilkoff.workers.dev"

# Similarity-weighted nearest-neighbor comp model (PRICING_PLAYBOOK §6.2 / §6.4).
# Each factor contributes a score; a card's comps are its top-K most-similar
# priced peers, regardless of which COMBINATION of factors got them there. A
# strict ladder forces treatment to match at every level, which means a /5 Hex
# Inspired Ink could never see a /5 Hex Battlefoil as a comp even though those
# share the more-scarcity-defining factor (printRun=5). The combination model
# fixes that — same /N + same weapon + similar power can beat same-treatment +
# different /N when /N is the dominant scarcity signal.
#
# Weights, ordered by §6.4 priority. These are PRIORS not learned coefficients
# (§6.3 — real weights get fit when sold-comp data accrues), but the ordering
# is principled: printRun is Feature 0 (the hardest scarcity signal); treatment
# + weapon are the rarity class; variation + cardType are identity-of-thing
# (First Edition vs reprint, Hero vs Play); power tier is gameplay value; hero
# is intentionally weak (Feature 6 — a multiplier, not a primary axis).
SIM_WEIGHTS = {
    "printRun_match":     10,   # /5 finds /5 (hardest scarcity signal, §6.4 Feature 0)
    "treatment_match":     5,   # same print-variant family
    "weapon_match":        4,   # same rarity tier (Brawl Common → Super 1-of-1)
    "variation_match":     3,   # First Edition / 2026 / athlete-debut
    "cardType_match":      3,   # Hero ≠ Play ≠ HotDog ≠ Sealed
    "power_tier_match":    2,   # gameplay value bucket
    "both_unserialized":   2,   # weak commonality between two non-/N cards
    "hero_match":          1,   # §6.2 — secondary multiplier, NEVER primary
}
MIN_SIM   = 9      # treatment+weapon = 9, printRun alone = 10 — both qualify; below means too unrelated
MAX_SIM_GAP = 4    # comps within this many sim-points of the top comp are kept;
                   #   below means meaningfully-less-similar rarity class and mixing
                   #   them drags the median wrong (e.g., a /5 chase top-comp at
                   #   sim 14 next to sim-9 unserialized commons = $400 averaged
                   #   with $5 → emit nothing rather than that lie).
MAX_COMPS = 16     # cap the comp pool at the top-K most similar
CONF_AVG_SIM_MED = 14  # avg similarity of top comps to qualify for "med" confidence

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


def similarity(target, peer):
    """Combined-factor similarity score between two cards (target ↔ peer).
    Higher = closer comp. See SIM_WEIGHTS for the per-factor priors; the
    closest-comp model means whichever COMBINATION of factors gets the
    highest score wins, not a fixed-priority ladder."""
    s = 0
    # printRun is the hardest scarcity signal when both cards have it.
    t_pr, p_pr = target.get("printRun"), peer.get("printRun")
    if t_pr and p_pr and t_pr == p_pr:
        s += SIM_WEIGHTS["printRun_match"]
    elif (not t_pr) and (not p_pr):
        # Both unserialized — weak commonality (most catalog cards are this).
        s += SIM_WEIGHTS["both_unserialized"]
    # Rarity class.
    t_t = target.get("treatment")
    if t_t and t_t == peer.get("treatment"):
        s += SIM_WEIGHTS["treatment_match"]
    t_el = target.get("element")
    if t_el and t_el == peer.get("element"):
        s += SIM_WEIGHTS["weapon_match"]
    # Identity-of-thing.
    t_va = target.get("variation")
    if t_va and t_va == peer.get("variation"):
        s += SIM_WEIGHTS["variation_match"]
    t_ct = target.get("cardType")
    if t_ct and t_ct == peer.get("cardType"):
        s += SIM_WEIGHTS["cardType_match"]
    # Gameplay value bucket.
    t_pt = power_tier(target.get("power"))
    if t_pt != "na" and t_pt == power_tier(peer.get("power")):
        s += SIM_WEIGHTS["power_tier_match"]
    # Hero — explicitly weak per §6.2 (multiplier, not primary axis).
    t_h = target.get("hero")
    if t_h and t_h == peer.get("hero"):
        s += SIM_WEIGHTS["hero_match"]
    return s


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

    # ── Build the priced-comp pool ───────────────────────────────────────
    # Per-card tracker prices + Whatnot augmentation (per-card matches via
    # cardNumber resolution; treatment-level aggregates as synthetic comp
    # entries that share only treatment+weapon with targets).
    priced_pool = []  # [(card_dict_or_synthetic, price), …]
    for c in cards:
        bid = c.get("bobaId")
        if bid in prices:
            priced_pool.append((c, prices[bid][0]))

    # ── Whatnot augmentation ─────────────────────────────────────────────
    # Many treatments (mainstream battlefoils, color blasts, Inspired Ink)
    # trade more on Whatnot than eBay. Two-tier resolution per listing:
    #   (A) cardNumber parseable from title (e.g., "BLBF-15", "GLBF-365") →
    #       resolve to a specific catalog card → use as a per-card comp with
    #       full rarity factors.
    #   (B) only weapon word parseable → synthetic "comp entry" with only
    #       treatment+weapon set, so it contributes at similarity 9 (the
    #       treatment×weapon floor) to targets sharing those factors.
    # Asks × SOLD_HAIRCUT for both. Zero eBay quota.
    print("\nWhatnot augmentation:")
    cards_by_cn_fam = defaultdict(list)
    for c in cards:
        cn = c.get("cardNumber"); t = c.get("treatment")
        if cn and t:
            cards_by_cn_fam[(cn.upper(), treatment_family(t))].append(c)

    distinct_treatments = sorted({(c.get("treatment") or "") for c in cards if c.get("treatment")})
    # Coverage gap proxy: treatments where at least one (treatment, weapon)
    # has no per-card priced data. Cheap heuristic — we query everything
    # whose floor is sparse, since Whatnot scrape is cached at the edge.
    priced_tw = {(c.get("treatment") or "", c.get("element") or "NONE")
                 for c, _ in priced_pool if c.get("bobaId") not in (None,)}
    treatments_to_query = []
    for t_str in distinct_treatments:
        weapons_used = {(c.get("element") or "NONE") for c in cards
                        if c.get("bobaId") and (c.get("treatment") or "") == t_str}
        if any((t_str, w) not in priced_tw for w in weapons_used):
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
            price = float(li["price"]) * SOLD_HAIRCUT
            title = li.get("title") or ""
            # (A) cardNumber path — most precise.
            cn = parse_cardnumber_from_title(title)
            cands = cards_by_cn_fam.get((cn, fam), []) if cn else []
            chosen = None
            if len(cands) == 1:
                chosen = cands[0]
            elif len(cands) > 1:
                # Same cardNumber + treatment across multiple weapons (#057
                # FIRE/GLOW variant pairs). Disambiguate from title weapon.
                w_in_title = parse_weapon_from_title(title)
                if w_in_title:
                    for cand in cands:
                        if (cand.get("element") or "").upper() == w_in_title:
                            chosen = cand
                            break
            if chosen:
                priced_pool.append((chosen, price))
                matched_by_card += 1
                continue
            # (B) weapon-only fallback → synthetic comp entry (treatment +
            # weapon only, no other factors). It'll match targets sharing
            # treatment+weapon at similarity 9.
            w = parse_weapon_from_title(title)
            if w:
                synth = {"bobaId": WN_SENTINEL, "treatment": t_str, "element": w}
                priced_pool.append((synth, price))
                matched_by_treatment += 1
            else:
                dropped_unparseable += 1
        if i % 10 == 0:
            print(f"  ... {i}/{len(treatments_to_query)} treatments queried")
        time.sleep(0.6)
    print(f"  Whatnot listings → per-card matches: {matched_by_card}, "
          f"treatment-level aggregates: {matched_by_treatment}, "
          f"dropped (no cardNumber/weapon): {dropped_unparseable}")
    print(f"  priced comp pool size: {len(priced_pool)}")

    # ── Similarity-weighted nearest-neighbor comp selection ──────────────
    # For each target card, score every priced peer by combined-factor
    # similarity, keep those with sim ≥ MIN_SIM, sort descending, take the
    # top MAX_COMPS, and compute an outlier-trimmed percentile band on their
    # prices. Honest provenance (#058): the basis names *which combination*
    # of factors got us to those comps — not a fixed-level label.
    print("\nFinding closest comps for each card…")
    estimates = {}
    n_skipped_too_few = 0
    for c in cards:
        bid = c.get("bobaId")
        if not bid:
            continue
        # Score every priced peer; skip self.
        scored = []
        for peer, price in priced_pool:
            if peer.get("bobaId") == bid:
                continue
            s = similarity(c, peer)
            if s >= MIN_SIM:
                scored.append((s, price))
        if len(scored) < MIN_CARDS:
            n_skipped_too_few += 1
            continue
        # Sort by similarity desc; KEEP only comps within MAX_SIM_GAP of the
        # top one (mixing meaningfully-less-similar peers drags the median
        # wrong — e.g., a /5 chase whose top comp is a same-treatment /50 at
        # sim 14 shouldn't be averaged with Base Set commons at sim 9). Then
        # take the top MAX_COMPS of what remains.
        scored.sort(key=lambda x: -x[0])
        top_sim = scored[0][0]
        scored = [(s, p) for s, p in scored if s >= top_sim - MAX_SIM_GAP]
        if len(scored) < MIN_CARDS:
            n_skipped_too_few += 1
            continue
        top = scored[:MAX_COMPS]
        sims = [s for s, _ in top]
        comp_prices = sorted(p for _, p in top)
        n = len(comp_prices)
        avg_sim = sum(sims) / n
        # Outlier-trim the price band (drop top/bottom 10% for n ≥ 10) so a
        # single unicorn (e.g., $19,500 Founding Hero) can't drag the high.
        if n >= 10:
            trim = max(1, n // 10)
            band = comp_prices[trim:-trim]
        else:
            band = comp_prices
        nb = len(band)
        def pct(q):
            return band[max(0, min(nb - 1, int(q * (nb - 1) + 0.5)))]
        estimates[bid] = {
            "low":    round(pct(0.25), 2),
            "mid":    round(pct(0.50), 2),
            "high":   round(pct(0.75), 2),
            "n":      n,
            "avgSim": round(avg_sim, 1),
            "topSim": top[0][0],
            "basis":  "closest comparable cards (combined-factor similarity)",
            # "med" only when comps are tight AND there are enough of them; the
            # closest-comp model + ask-derived data won't yield "high" today.
            "conf":   "med" if (avg_sim >= CONF_AVG_SIM_MED and n >= CONF_HIGH) else "low",
        }

    print(f"estimates produced: {len(estimates)} / {len(cards)} cards "
          f"({100*len(estimates)//max(1,len(cards))}% coverage)")
    print(f"  cards skipped (fewer than {MIN_CARDS} comps at sim≥{MIN_SIM}): {n_skipped_too_few}")
    # Distribution of avg-similarity to see how tight the comps are
    bins = [0, 10, 13, 16, 20, 99]
    bin_labels = ["9-10 (treatment+weapon)", "10-13", "13-16", "16-20", "20+ (very tight)"]
    bcounts = [0] * (len(bins) - 1)
    for e in estimates.values():
        for i in range(len(bins) - 1):
            if bins[i] <= e["avgSim"] < bins[i + 1]:
                bcounts[i] += 1
                break
    for label, n in zip(bin_labels, bcounts):
        print(f"  avgSim {label}: {n} cards")

    if args.dry:
        print("(dry run — not writing)")
        return

    import datetime
    payload = {
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "soldHaircut": SOLD_HAIRCUT,
        "minCards":    MIN_CARDS,
        "minSim":      MIN_SIM,
        "maxComps":    MAX_COMPS,
        "weights":     SIM_WEIGHTS,
        "method":      "nearest_comparable_v1",
        "estimates":   estimates,
    }
    json.dump(payload, open(OUT, "w"), separators=(",", ":"))
    size_kb = os.path.getsize(OUT) // 1024
    print(f"wrote {OUT} ({size_kb} KB)")


if __name__ == "__main__":
    main()
