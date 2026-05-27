#!/usr/bin/env python3
"""Build the BoBA rarity reference model for the price estimator (Tier 4).

Encodes the OFFICIAL rarity structure from the 2026-Edition + Alpha-Update
"Parallels, Rarity & Checklist" guides (promo.bobattlearena.com) as a FACTUAL
reference table, then validates it across the full catalog.

This is NOT a price model and NOT a set of learned weights — per
PRICING_PLAYBOOK.md §6.2-§6.4, the real feature weights are LEARNED from
comps once Tier 1 data exists. This file emits the ordinal tiers + observed
serialization + distribution that the estimator consumes as features/priors,
plus a transparent, clearly-labeled COLD-START scarcity score used only to
sanity-check that the tiers order cards believably before any comp exists
(and as the fallback for comp-less cards). The cold-start weights live in the
emitted JSON so they're tunable and replaceable, not buried in code.

Source of truth precedence (PRICING_PLAYBOOK §6.4):
  1. Observed `printRun` on the card (the real /N we pulled) — a fact, dominant.
  2. Weapon rarity tier (Common->Rare->Ultra->Secret->1of1).
  3. Distribution tier (which SKU a parallel comes from).
  4. Power, card class, treatment population, hero (secondary).

Run:  python3 scripts/build_rarity_model.py            # writes + sanity report
      python3 scripts/build_rarity_model.py --check    # report only, no write
"""
import json
import os
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "assets/data/cards.json")
OUT = os.path.join(ROOT, "assets/data/rarity-model.json")

# --- Feature 1: Weapon rarity tier (2026 Weapons chart; ordinal) ------------
# ordinal 1..5, low=common. ALT/CYBER/NONE/"" are not on the weapon ladder.
WEAPON_TIER = {
    "BRAWL": [1, "common"], "STEEL": [1, "common"],
    "FIRE": [2, "rare"], "ICE": [2, "rare"],
    "GLOW": [3, "ultra_rare"],
    "HEX": [4, "secret_rare"], "GUM": [4, "secret_rare"],
    "SUPER": [5, "one_of_one"],
}
FOIL_ONLY_WEAPONS = ["GLOW", "HEX", "GUM", "SUPER"]  # foil-only = scarcity bump

# --- Feature 2: Distribution tier (2026 Parallels & Inserts chart) ----------
# 0 base/non-parallel · 1 all-SKU · 2 hobby/jumbo · 3 mega/blaster ·
# 4 single-SKU · 5 superfoil 1/1.  Keys are exact catalog `treatment` strings.
DIST_LABELS = {0: "base", 1: "all_sku", 2: "hobby_jumbo",
               3: "mega_blaster", 4: "single_sku", 5: "superfoil_1of1"}
TREATMENT_DIST = {
    # base / non-parallel
    "Base Set": 0, "Paper": 0, "Battlefoil": 1,
    # found in ALL SKUs
    "Inspired Ink Battlefoil": 1, "Inspired Ink Superfoil": 1,
    "Inspired Ink Bubble Gum Battlefoil": 1,
    "Alpha Battlefoil": 1, "80's Rad Battlefoil": 1, "Colosseum Battlefoil": 1,
    "Logofoil": 1, "Blizzard Battlefoil": 1, "Miami Ice Battlefoil": 1,
    "Fire Tracks Battlefoil": 1, "Mixtape Battlefoil": 1,
    # Jumbo / Hobby only
    "Inspired Ink Metallic Battlefoil": 2,
    "Red Battlefoil": 2, "Silver Battlefoil": 2, "Blue Battlefoil": 2,
    "Orange Battlefoil": 2, "Green Battlefoil": 2, "Pink Battlefoil": 2,
    "Grandma's Linoleum Battlefoil": 2, "Bubble Gum Battlefoil": 2,
    # Double Mega & Blaster
    "Great Grandma's Linoleum Battlefoil": 3, "Grillin' Battlefoil": 3,
    "Chillin' Battlefoil": 3, "Slime Battlefoil": 3, "Icon Battlefoil": 3,
    # Double Mega only
    "Bonus Plays": 4, "Power Glove Battlefoil": 4,
    # Blaster only
    "Headlines Battlefoil": 4, "Blue Headlines Battlefoil": 4,
    "Red Headlines Battlefoil": 4, "Orange Headlines Battlefoil": 4,
    # Superfoil 1/1
    "Superfoil": 5,
}
# Treatments NOT named in the 2026 guide fall back to a catalog-population
# scarcity proxy (smaller population => rarer). Reported as `unmapped` so the
# gaps are explicit, never silently guessed.

# --- Cold-start scarcity weights (transparent, tunable, REPLACEABLE) --------
# Used only to (a) sanity-rank before comps exist and (b) seed comp-less cards.
# Replaced by the learned hedonic model once Tier 1 comps land (§6.3).
COLD_START = {
    "_note": "Cold-start heuristic ONLY. Replaced by learned weights once "
             "comps exist (PRICING_PLAYBOOK §6.3). printRun is the dominant "
             "factual signal; the rest are ordinal priors.",
    "printRun_score": {"5": 58, "10": 50, "25": 42, "50": 34},
    "printRun_default_cap": [20, 60],   # for any other /N: clamp 250/N
    "weapon_tier_score": {"1": 2, "2": 10, "3": 18, "4": 26, "5": 45},
    "dist_tier_score": {"0": 0, "1": 3, "2": 10, "3": 14, "4": 18, "5": 45},
    "foil_only_bonus": 5,
    "power_lift_div": 12,        # (power-100)/12, clamped [-2, 8]
    "one_of_one_score": 100,     # SUPER weapon or printRun==1
}


def load_cards():
    with open(CATALOG) as f:
        return json.load(f)


def population_by_treatment(cards):
    return Counter((c.get("treatment") or "(none)") for c in cards)


def cold_start_score(card, pop, pop_rank):
    """Transparent cold-start scarcity score (0-100). NOT the learned model."""
    w = COLD_START
    weapon = (card.get("element") or "").upper()
    pr = card.get("printRun")
    if weapon == "SUPER" or pr == 1:
        return w["one_of_one_score"]
    score = 0.0
    if pr:
        s = w["printRun_score"].get(str(pr))
        if s is None:
            lo, hi = w["printRun_default_cap"]
            s = max(lo, min(hi, 250 / pr))
        score += s
    tier = WEAPON_TIER.get(weapon, [0])[0]
    score += w["weapon_tier_score"].get(str(tier), 0)
    t = card.get("treatment") or "(none)"
    dist = TREATMENT_DIST.get(t)
    if dist is not None:
        score += w["dist_tier_score"].get(str(dist), 0)
    else:
        # population-proxy fallback: rarer treatment => higher (cap at dist t4)
        score += round(18 * (1 - pop_rank), 1)
    if weapon in FOIL_ONLY_WEAPONS:
        score += w["foil_only_bonus"]
    score += max(-2, min(8, ((card.get("power") or 100) - 100) / w["power_lift_div"]))
    return round(score, 1)


def build():
    cards = load_cards()
    pop = population_by_treatment(cards)
    # population percentile per treatment (0=rarest .. 1=most common)
    ordered = [t for t, _ in pop.most_common()]
    n = len(ordered)
    pop_rank = {t: (n - 1 - i) / (n - 1) for i, t in enumerate(ordered)}  # 1=common

    treatments = {}
    for t, count in pop.most_common():
        dist = TREATMENT_DIST.get(t)
        treatments[t] = {
            "population": count,
            "distributionTier": dist,
            "distributionLabel": DIST_LABELS.get(dist) if dist is not None else None,
            "mappedFromGuide": dist is not None,
        }

    model = {
        "_generator": "scripts/build_rarity_model.py",
        "_source": "promo.bobattlearena.com Alpha-Update + 2026-Edition "
                   "Parallels/Rarity/Checklist guides; catalog printRun field",
        "_doc": "PRICING_PLAYBOOK.md §6.2-§6.4. FACTUAL reference table for the "
                "Tier 4 estimator. Weights are LEARNED from comps; coldStart is "
                "only the pre-comp fallback.",
        "weaponTier": {k: {"ordinal": v[0], "label": v[1]} for k, v in WEAPON_TIER.items()},
        "foilOnlyWeapons": FOIL_ONLY_WEAPONS,
        "distributionTierLabels": DIST_LABELS,
        "treatments": treatments,
        "coldStartWeights": COLD_START,
    }

    # ---- sanity report ----
    scored = []
    for c in cards:
        if c.get("cardType") == "Sealed Product":
            continue  # sealed isn't a single-card rarity
        s = cold_start_score(c, pop, pop_rank.get(c.get("treatment") or "(none)", 1.0))
        scored.append((s, c))
    scored.sort(key=lambda x: -x[0])

    def line(c):
        return (f"{c.get('cardNumber',''):<12} {(c.get('hero') or c.get('name') or '')[:18]:<18} "
                f"{(c.get('element') or '-'):<6} pr={str(c.get('printRun')):<5} "
                f"pw={str(c.get('power')):<4} {(c.get('treatment') or '')[:34]}")

    print(f"\n{'='*78}\nRARITY MODEL — sanity report ({len(scored)} non-sealed cards)\n{'='*78}")
    mapped = sum(1 for t in treatments.values() if t["mappedFromGuide"])
    print(f"treatments mapped to a guide distribution tier: {mapped}/{len(treatments)}")
    print(f"unmapped (population-proxy fallback): "
          f"{[t for t,d in treatments.items() if not d['mappedFromGuide']]}")
    pr_present = sum(1 for _, c in scored if c.get("printRun"))
    print(f"cards with observed printRun: {pr_present}")
    print(f"\n--- TOP 15 rarest (cold-start) ---")
    for s, c in scored[:15]:
        print(f"  {s:6.1f}  {line(c)}")
    print(f"\n--- BOTTOM 10 most common ---")
    for s, c in scored[-10:]:
        print(f"  {s:6.1f}  {line(c)}")
    print(f"\n--- score buckets ---")
    buckets = Counter()
    for s, _ in scored:
        buckets[int(s // 10) * 10] += 1
    for b in sorted(buckets, reverse=True):
        print(f"  {b:3d}-{b+9:<3d}: {buckets[b]}")
    return model


def main():
    model = build()
    if "--check" in sys.argv:
        print(f"\n[--check] not writing {os.path.relpath(OUT, ROOT)}")
        return
    with open(OUT, "w") as f:
        json.dump(model, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"\nwrote {os.path.relpath(OUT, ROOT)} "
          f"({len(model['treatments'])} treatments)")


if __name__ == "__main__":
    main()
