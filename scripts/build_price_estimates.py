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
RARITY_MODEL = os.path.join(REPO, "assets", "data", "rarity-model.json")
OUT = os.path.join(REPO, "assets", "data", "price-estimates.json")
TRACKER_DIR = os.path.join(REPO, "workers", "pricing-tracker")

SOLD_HAIRCUT = 0.82     # asking → estimated-sold (asks run ~10-25% above sold)
MIN_CARDS = 3           # need at least this many comps for any estimate
# Rarity-premium multipliers for canonical 1-of-1 cards (SUPER weapon)
# when no tier-locked tracker peers exist. Applied to the same-treatment
# closest-comp band as a wide hedged range. Reflects sports-card market
# behavior where 1-of-1 chase cards trade at 5–50× same-treatment commons.
# Tunable — Ben can fit these once real Super tracker data accrues and
# the relationship to same-treatment comps can be measured.
SUPER_PREMIUM_LOW  = 35
SUPER_PREMIUM_MID  = 100
SUPER_PREMIUM_HIGH = 300
# Weapon-tier extrapolation multipliers for HEX/GUM (tier 4 "secret_rare")
# when no same-weapon peers exist within the target's treatment. Applied to
# cross-weapon same-treatment comps as a rarity premium. Reflects HEX/GUM
# pricing typically running 3-10× vs same-treatment STEEL/BRAWL commons.
# Smaller spread than SUPER (5/15/50 → 25/75/250 → 35/100/300 progression
# above) because HEX/GUM populations vary card-to-card (not strict 1-of-1)
# so the band is tighter. Tunable in response to audit drift.
WEAPON_TIER4_PREMIUM_LOW  = 3
WEAPON_TIER4_PREMIUM_MID  = 6
WEAPON_TIER4_PREMIUM_HIGH = 12
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
    "variation_match":     3,   # First Edition / 2026 / athlete-debut / Hobby Box
    "cardType_match":      3,   # Hero ≠ Play ≠ HotDog ≠ Sealed Product
    "set_match":           3,   # era affinity; CRITICAL for Sealed (no treatment / weapon)
                                # and helpful refinement for normal cards across reissues
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
    # Set / era — load-bearing for Sealed Products (which have no treatment
    # or weapon, so without this they can't reach MIN_SIM); a useful refinement
    # for normal cards across reissues. Same Alpha Update Battlefoil → bonus.
    t_set = target.get("set")
    if t_set and t_set == peer.get("set"):
        s += SIM_WEIGHTS["set_match"]
    # Gameplay value bucket.
    t_pt = power_tier(target.get("power"))
    if t_pt != "na" and t_pt == power_tier(peer.get("power")):
        s += SIM_WEIGHTS["power_tier_match"]
    # Hero — explicitly weak per §6.2 (multiplier, not primary axis).
    t_h = target.get("hero")
    if t_h and t_h == peer.get("hero"):
        s += SIM_WEIGHTS["hero_match"]
    return s


def pull_sealed_listings(bobaIds):
    """Return {bobaId: [raw_active_prices]} — RAW prices, not medians. The
    Sealed-product path computes its own filtered median (it needs to drop
    single-card noise that creeps in via broad search queries — e.g., a
    'Battle Trainer Kit' query hitting any listing whose title mentions
    those words). Empty dict when bobaIds is empty or the query fails."""
    if not bobaIds:
        return {}
    in_clause = ",".join("'" + bid.replace("'", "''") + "'" for bid in bobaIds)
    sql = (
        f"SELECT boba_id, price_usd FROM listings "
        f"WHERE vanished_at IS NULL AND price_usd > 0 AND boba_id IN ({in_clause});"
    )
    out = subprocess.run(
        ["npx", "wrangler", "d1", "execute", "boba-pricing", "--remote", "--json", "--command", sql],
        cwd=TRACKER_DIR, capture_output=True, text=True, timeout=180,
    )
    if out.returncode != 0:
        print(out.stderr[-500:], file=sys.stderr)
        return {}
    by_card = defaultdict(list)
    for r in json.loads(out.stdout)[0]["results"]:
        by_card[r["boba_id"]].append(r["price_usd"])
    return by_card


# Sealed products are per-SKU markets — single-card listings sometimes leak
# into the search results because the catalog product name shares words
# with card titles (e.g., a "Battle Trainer Kit" query matches single cards
# whose titles mention those words). Filter clearly-too-cheap listings out
# before computing the median; the legitimate Sealed market starts well
# above single-card territory.
SEALED_MIN_PRICE = 10


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
    # Load the canonical rarity model — used below to enforce strict
    # treatment-match for rare-tier targets (DECISIONS.md #064 cross-tier
    # leakage fix) and the existing SUPER tier-lock (#063).
    rarity_model = json.load(open(RARITY_MODEL))
    # treatments[name].distributionTier: 0=base, 1=all_sku, 2=hobby_jumbo,
    # 3=mega_blaster, 4=single_sku, 5=superfoil_1of1. Tiers ≥ 2 are
    # structurally rarer pull-rates → require same-treatment peers (no
    # cross-treatment leakage from common Battlefoils).
    treatment_tier = {name: (meta.get("distributionTier") or 0)
                      for name, meta in rarity_model.get("treatments", {}).items()}
    weapon_tier = {name: (meta.get("ordinal") or 0)
                   for name, meta in rarity_model.get("weaponTier", {}).items()}
    # Low-population printRun buckets — same logic as SUPER. /5 is Hex
    # Inspired Ink chase; /1 is SUPER. /10, /25, /50 have wider markets
    # (LeBoss IIS-style) so don't strict-require printRun match for them.
    STRICT_PRINTRUN = {1, 5}
    # SUPER weapon is canonically 1-of-1 per assets/data/rarity-model.json
    # (label "one_of_one", distributionTier 5). Super cards aren't
    # numbered — they ARE the unique copy — so OCR can't pull a "/1"
    # stamp and `printRun` stays None on every Super card in the
    # catalog. Without this inference the similarity scorer can only
    # cluster Super peers by treatment_match (5) + weapon_match (4) =
    # 9, the bare MIN_SIM — well below the printRun_match=10 bonus the
    # rarity model intends, so the closest-comp pool fills with
    # cheaper Battlefoil commons that share weapon-tier-2 attributes.
    # Ben's audit 2026-05-29 found 444 of 454 SUPER cards estimated
    # under $10 (median $3.07) — wrong for the rarest treatment by
    # multiple orders of magnitude. Inferring printRun=1 here makes
    # the model cluster Super↔Super exclusively (sim ≥ 21 vs
    # Super↔non-Super at ≤17, outside MAX_SIM_GAP=4), so the estimator
    # either matches actual Super tracker comps OR honestly emits
    # nothing — never the lie.
    super_inferred = 0
    for c in cards:
        if c.get("element") == "SUPER" and c.get("printRun") is None:
            c["printRun"] = 1
            super_inferred += 1
    if super_inferred:
        print(f"inferred printRun=1 on {super_inferred} SUPER cards "
              f"(rarity-model.json says SUPER is one_of_one — Ben's 2026-05-29 audit)")
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
    dropped_treatment_mismatch = 0

    # Title-parsed treatment matcher (DECISIONS.md #064 — cross-treatment
    # pool contamination fix). The Whatnot search endpoint does LOOSE word
    # matching: a query for "Inspired Ink Metallic Battlefoil" returns
    # listings actually titled "Inspired Ink Battlefoil" (no "Metallic") —
    # they share most words and Whatnot doesn't enforce phrase precision.
    # Pre-fix, the script created a synthetic comp entry labeled with the
    # SEARCH-QUERY treatment, so an IIB listing at $200 got booked as an
    # IIMBF synthetic comp at $200, polluting the rarer treatment's pool
    # and flattening 240 IIMBF cards to wrong common-treatment prices.
    # Fix: parse the treatment from the listing TITLE (longest match
    # wins → most specific), and use THAT for the synthetic entry's
    # treatment field. When the title-parsed treatment disagrees with
    # the search query, the listing still contributes — to its CORRECT
    # treatment's pool — but the rarer treatment's pool stays honest.
    # Listings with no parseable treatment in the title get dropped.
    treatments_by_len = sorted(
        {t for t in distinct_treatments if t},
        key=lambda s: -len(s),
    )

    def parse_treatment_from_title(title):
        """Return the longest treatment whose lowercase form appears as a
        substring of the lowercase title. None if none match. Substring is
        sufficient because Whatnot listings use the treatment name verbatim
        ("Inspired Ink Metallic Battlefoil"), and the catalog's treatment
        strings are distinct enough that longest-match disambiguates
        ("Inspired Ink Metallic Battlefoil" wins over "Inspired Ink
        Battlefoil" wins over "Battlefoil"). Length-sorted match is the
        same shape iOS / web / Android scan-result resolvers use."""
        if not title:
            return None
        tl = title.lower()
        for t in treatments_by_len:
            if t.lower() in tl:
                return t
        return None

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
            # (B) weapon-only fallback → synthetic comp entry. The
            # synthetic's treatment is parsed FROM THE TITLE, not taken
            # from the search query, because Whatnot search returns
            # treatment-mismatched listings (see comment block above on
            # the title-parser). If no treatment can be parsed from the
            # title, the listing is genuinely ambiguous and we drop it.
            t_in_title = parse_treatment_from_title(title)
            w = parse_weapon_from_title(title)
            if not t_in_title or not w:
                if not t_in_title and not w:
                    dropped_unparseable += 1
                else:
                    # Either treatment or weapon missing — can't anchor
                    # the synthetic in the right pool.
                    dropped_treatment_mismatch += 1
                continue
            synth = {"bobaId": WN_SENTINEL, "treatment": t_in_title, "element": w}
            priced_pool.append((synth, price))
            matched_by_treatment += 1
        if i % 10 == 0:
            print(f"  ... {i}/{len(treatments_to_query)} treatments queried")
        time.sleep(0.6)
    print(f"  Whatnot listings → per-card matches: {matched_by_card}, "
          f"treatment-level aggregates: {matched_by_treatment}, "
          f"dropped (treatment-mismatch): {dropped_treatment_mismatch}, "
          f"dropped (no cardNumber/weapon): {dropped_unparseable}")
    print(f"  priced comp pool size: {len(priced_pool)}")

    # ── Similarity-weighted nearest-neighbor comp selection ──────────────
    # For each target card, score every priced peer by combined-factor
    # similarity, keep those with sim ≥ MIN_SIM, sort descending, take the
    # top MAX_COMPS, and compute an outlier-trimmed percentile band on their
    # prices. Honest provenance (#058): the basis names *which combination*
    # of factors got us to those comps — not a fixed-level label.
    # ── Sealed Products — per-SKU direct pricing, NOT comparability ─────
    # Sealed (Hobby Box, Blaster Case, Trainer Kit, etc.) are fundamentally
    # different from cards: each Sealed is its own market. A Griffey Hobby
    # Box and a Tecmo Hobby Box don't share a price baseline. The similarity
    # model would either skip Sealed (no comparable card has matching
    # treatment/weapon/hero) or wrongly average two unrelated SKUs onto one
    # median. So Sealed gets its own path: use the median of THIS card's
    # own listings (curated per-SKU eBay queries via scripts/crawl_sealed_
    # products.py), filtered to drop single-card noise. SOLD_HAIRCUT applies
    # the same way (active ask → estimated-sold).
    print("\nSealed Product direct pricing:")
    sealed_cards = [c for c in cards if (c.get("cardType") or "") == "Sealed Product"]
    sealed_bobaIds = [c["bobaId"] for c in sealed_cards if c.get("bobaId")]
    sealed_listings = pull_sealed_listings(sealed_bobaIds)
    sealed_estimates = {}
    for c in sealed_cards:
        bid = c.get("bobaId")
        if not bid:
            continue
        raw = sealed_listings.get(bid, [])
        kept = sorted(p for p in raw if p >= SEALED_MIN_PRICE)
        if len(kept) < MIN_CARDS:
            continue
        after = [p * SOLD_HAIRCUT for p in kept]
        n = len(after)
        if n >= 10:
            trim = max(1, n // 10)
            band = after[trim:-trim]
        else:
            band = after
        nb = len(band)
        def pct(q, b=band, m=nb):
            return b[max(0, min(m - 1, int(q * (m - 1) + 0.5)))]
        sealed_estimates[bid] = {
            "low":    round(pct(0.25), 2),
            "mid":    round(pct(0.50), 2),
            "high":   round(pct(0.75), 2),
            "n":      n,
            "avgSim": 0,
            "topSim": 0,
            "basis":  "direct eBay listings for this SKU (Sealed Product)",
            "conf":   "med" if n >= 5 else "low",
        }
    print(f"  Sealed SKUs with priced listings: {len([b for b in sealed_listings if sealed_listings[b]])}")
    print(f"  Sealed estimates produced (≥{MIN_CARDS} listings ≥ ${SEALED_MIN_PRICE}): {len(sealed_estimates)}")
    sealed_bid_set = {c.get("bobaId") for c in sealed_cards if c.get("bobaId")}

    print("\nFinding closest comps for each card…")
    estimates = {}
    # Seed with Sealed estimates so they're written to the artifact. Sealed
    # cards are SKIPPED in the similarity loop below — they're already done.
    estimates.update(sealed_estimates)
    n_skipped_too_few = 0
    for c in cards:
        bid = c.get("bobaId")
        if not bid:
            continue
        # Sealed Products were handled above with per-SKU direct pricing —
        # skip them here so the similarity model doesn't try (and fail) to
        # find comps for products that don't share rarity-class semantics.
        if bid in sealed_bid_set:
            continue
        # Tier-locked comps for canonical 1-of-1 cards. SUPER weapon is
        # definitionally one-of-one per assets/data/rarity-model.json
        # (label "one_of_one", distributionTier 5). When Super tracker
        # comps exist, use them exclusively — the rarity tier IS the
        # signal, and cross-tier mixing misrepresents the market.
        #
        # When no Super peer has tracker data (today's state — Ben's
        # 2026-05-29 audit verified 0 across listings, sold_events,
        # Whatnot, and live eBay), we DON'T emit nothing — that loses
        # the user signal entirely. Instead we fall back to same-
        # treatment-family peers WITH a rarity-tier premium multiplier
        # + a wider hedged band, marked clearly as 'rarity-extrapolated'
        # so the UI can show appropriate caveats. The multiplier
        # matches sports-card market behavior where 1-of-1 chase cards
        # trade at 5–50× same-treatment commons (low / mid / high).
        is_super_target = (c.get("element") == "SUPER")
        if is_super_target:
            super_peers = [(p, pr) for p, pr in priced_pool
                           if p.get("element") == "SUPER"]
        else:
            super_peers = []
        # Prefer Super-only peers when any exist; otherwise fall through
        # to the full pool and apply the rarity premium downstream.
        rarity_extrapolated = False
        if is_super_target and super_peers:
            eligible_peers = super_peers
        elif is_super_target:
            eligible_peers = priced_pool
            rarity_extrapolated = True   # gated on Super-target with no
                                         # tier-locked peers
        else:
            eligible_peers = priced_pool
        # In rarity-extrapolated mode the catalog's canonical `printRun=1`
        # on Super cards (DECISIONS.md #063) actively HURTS fallback
        # matching: the cross-tier pool has zero Super peers, so neither
        # `printRun_match` (needs both sides equal) nor `both_unserialized`
        # (needs both None) fires — every comp scores 2 points lower than
        # before the catalog change. That cost cascades: many Inspired Ink
        # Superfoil cards (Palmer SFA-24, et al.) dropped below MIN_SIM=9
        # and now skip in the hedged path that's supposed to catch them.
        # Score the target with printRun virtualized to None for fallback
        # scoring so both_unserialized fires against the pool's typical
        # unnumbered peers. The catalog's printRun=1 stays canonical for
        # everything else (UI chip + future tier-locked matching once
        # Super tracker data accrues + every other consumer).
        target_for_scoring = {**c, "printRun": None} if rarity_extrapolated else c
        # Strict-match gating for structurally-rare classes (DECISIONS.md
        # #064). Combined-factor scoring is the right model for common
        # cards — same weapon + same variation + same cardType + power
        # tier easily reaches MIN_SIM regardless of treatment, which is
        # why a /5 Inspired Ink Hex can usefully comp against a /5 Hex
        # Battlefoil (printRun is the dominant scarcity signal). But
        # for treatments at distributionTier ≥ 2 (hobby_jumbo / mega_
        # blaster / single_sku / superfoil_1of1) the TREATMENT is the
        # dominant scarcity signal, and cross-treatment matches drag
        # the price toward the common pool. Pre-fix, IIMBF STEEL cards
        # (tier 2) priced at $2.25 because they matched Beltré-debut
        # peers across cheaper treatments. Same logic for /1 and /5
        # printRun — those low-pop buckets must find same-printRun
        # peers or honestly emit nothing.
        t_target = c.get("treatment")
        target_treatment_tier = treatment_tier.get(t_target, 0)
        # Strict gates apply only OUTSIDE rarity-extrapolated mode. The
        # rarity_extrapolated path is the SUPER (#063 + #064) fallback
        # that intentionally broadens the pool and applies a hedged
        # multiplier — gating it on same-treatment would empty the
        # fallback pool too (Superfoil has 134 catalog cards × 0
        # tracker comps as of 2026-05-29). Both strict gates skip in
        # that mode; the multiplier carries the rarity premium instead.
        #
        # Strict-treatment applies to EVERY non-Base target (tier ≥ 1).
        # Base Set commons (tier 0) freely cross-comp because the
        # market is genuinely homogeneous — a Base Set FIRE LeBoss
        # comps a Base Set FIRE Maverick at $3-5 across the catalog.
        # Non-Base treatments (Battlefoil family, Inspired Ink family,
        # Blasts, Headlines, etc.) each have their OWN market and the
        # combined-factor scoring leaks low-priced Base FIRE peers
        # into chase IIB FIRE pools at sim 11 (weapon+cardType+power
        # +both_unserialized) — dragging IIB FIRE Mullin Debut to
        # $2.86 against LeBoss Base Set FIRE commons at $4. The
        # treatment-tier gate forces non-Base targets to find peers
        # within their own treatment market or honestly skip. Tier ≥ 2
        # already required this; tier ≥ 1 extends to mainstream
        # Battlefoils + Inspired Ink. (DECISIONS.md #064.)
        strict_treatment = (target_treatment_tier >= 1) and not rarity_extrapolated
        pr_target = c.get("printRun")
        strict_printrun = (pr_target in STRICT_PRINTRUN) and not rarity_extrapolated
        # Strict-weapon for tier ≥ 4 (HEX, GUM, SUPER — the secret-rare
        # and one-of-one weapons per rarity-model.json). Pre-fix
        # examples: RAD-306 Time 80's Rad Battlefoil HEX estimated at
        # $12.30 because the 80's Rad Battlefoil treatment has zero
        # same-weapon HEX D1 listings — only 4 BRAWL, 4 ICE, 2 STEEL,
        # at \$15-\$30. The HEX target cross-comped those and adopted
        # their low median, drastically misrepresenting tier-4 rarity.
        # Fix: HEX/GUM targets must find same-weapon peers within
        # their treatment market or skip honestly. SUPER's path is
        # rarity_extrapolated (already gated out via 'not
        # rarity_extrapolated'); the tier-locked SUPER branch with
        # printRun=1 + super_peers already enforces same-weapon
        # implicitly.
        t_element = c.get("element")
        target_weapon_tier = weapon_tier.get(t_element, 0)
        strict_weapon = (target_weapon_tier >= 4) and not rarity_extrapolated
        # Score every priced peer; skip self.
        def score_peers(peers, *, enforce_treatment, enforce_printrun, enforce_weapon):
            out = []
            for peer, price in peers:
                if peer.get("bobaId") == bid:
                    continue
                if enforce_treatment and peer.get("treatment") != t_target:
                    continue
                if enforce_printrun and peer.get("printRun") != pr_target:
                    continue
                if enforce_weapon and peer.get("element") != t_element:
                    continue
                s = similarity(target_for_scoring, peer)
                if s >= MIN_SIM:
                    out.append((s, price))
            return out

        scored = score_peers(
            eligible_peers,
            enforce_treatment=strict_treatment,
            enforce_printrun=strict_printrun,
            enforce_weapon=strict_weapon,
        )
        # Weapon-tier extrapolation fallback for tier-4 HEX/GUM. When
        # the strict-weapon gate yields too few peers, retry WITHOUT
        # weapon gating and apply a rarity-tier premium multiplier
        # downstream (mirrors SUPER's rarity_extrapolated path #063 +
        # #064). Reflects HEX/GUM trading at 3-10× vs same-treatment
        # commons even when no direct-weapon comps exist.
        weapon_extrapolated = False
        if strict_weapon and len(scored) < MIN_CARDS:
            scored = score_peers(
                eligible_peers,
                enforce_treatment=strict_treatment,
                enforce_printrun=strict_printrun,
                enforce_weapon=False,
            )
            if len(scored) >= MIN_CARDS:
                weapon_extrapolated = True
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
        gap_kept = [(s, p) for s, p in scored if s >= top_sim - MAX_SIM_GAP]
        gap_narrow_fallback = False
        if len(gap_kept) < MIN_CARDS:
            # Gap-filter clipped too aggressively — top 1-2 comps are
            # unusually-tight matches (e.g., the 2 Whatnot per-card hits
            # for BLBF-249/255 GLOW landing at sim 20-22 while the next
            # tier of cross-weapon same-treatment peers sits at sim 13-17).
            # Rather than skip the card (yields the missing-in-cluster
            # pattern audit #6 catches), fall back to top-MIN_CARDS
            # regardless of gap and mark conf="low". The honest answer
            # for these cluster-edge targets — a wider comp pool with
            # low confidence beats no estimate at all when the cluster
            # itself has the data. (DECISIONS.md #064.)
            scored = scored[:MIN_CARDS]
            gap_narrow_fallback = True
        else:
            scored = gap_kept
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
        low_raw, mid_raw, high_raw = pct(0.25), pct(0.50), pct(0.75)
        if rarity_extrapolated:
            # Super 1-of-1 with NO tier-locked comp data. Apply a rarity-
            # tier premium reflecting where 1-of-1 chase cards trade in
            # adjacent sports-card markets vs same-treatment commons.
            # Wide band hedges the right-tail uncertainty (a Maverick or
            # LeBoss 1-of-1 sits at the top end; an obscure-hero Super
            # sits at the floor). Better-than-silent, honestly labeled.
            # Multipliers are tunable — pre-tracker-data defaults.
            low_raw  *= SUPER_PREMIUM_LOW
            mid_raw  *= SUPER_PREMIUM_MID
            high_raw *= SUPER_PREMIUM_HIGH
            basis = (f"rarity-extrapolated from same-treatment comps "
                     f"(no Super tracker data yet; premium {SUPER_PREMIUM_LOW}–{SUPER_PREMIUM_HIGH}×)")
            conf = "low"
        elif weapon_extrapolated:
            # Tier-4 HEX/GUM with no same-weapon peers in this
            # treatment's pool — use cross-weapon same-treatment
            # comps as a base and apply the weapon-tier premium.
            low_raw  *= WEAPON_TIER4_PREMIUM_LOW
            mid_raw  *= WEAPON_TIER4_PREMIUM_MID
            high_raw *= WEAPON_TIER4_PREMIUM_HIGH
            basis = (f"rarity-extrapolated from same-treatment cross-weapon comps "
                     f"(no {t_element} peers in this treatment; premium "
                     f"{WEAPON_TIER4_PREMIUM_LOW}–{WEAPON_TIER4_PREMIUM_HIGH}×)")
            conf = "low"
        else:
            if gap_narrow_fallback:
                basis = ("closest comparable cards "
                         "(combined-factor similarity; few in-cluster peers — wide-gap fallback)")
                conf = "low"
            else:
                basis = "closest comparable cards (combined-factor similarity)"
                # "med" only when comps are tight AND there are enough of them;
                # the closest-comp model + ask-derived data won't yield "high".
                conf  = "med" if (avg_sim >= CONF_AVG_SIM_MED and n >= CONF_HIGH) else "low"
        estimates[bid] = {
            "low":    round(low_raw, 2),
            "mid":    round(mid_raw, 2),
            "high":   round(high_raw, 2),
            "n":      n,
            "avgSim": round(avg_sim, 1),
            "topSim": top[0][0],
            "basis":  basis,
            "conf":   conf,
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
