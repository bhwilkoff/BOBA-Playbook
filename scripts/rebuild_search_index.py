#!/usr/bin/env python3
"""Rebuild `assets/data/search-index.json` from the master cards.json.

The search index drives the card grid's text search and every facet
filter (weapon, set, treatment, etc.). After appending new records
(e.g. the OKC Thunder World Champions set) the index needs to surface
the new entries.

Each card's `searchTokens` array is the source of truth for tokenIndex
contributions; the per-facet sets (byHero, bySet, etc.) are derived
from each row's structured fields.
"""
from __future__ import annotations
import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC  = ROOT / "assets/data/cards.json"
DST  = ROOT / "assets/data/search-index.json"


def power_band(power) -> str | None:
    if power is None: return None
    try:
        p = int(power)
    except (TypeError, ValueError):
        return None
    if p <= 114:  return "low"        # ≤ 114 power
    if p <= 139:  return "mid"        # 115–139
    if p <= 164:  return "high"       # 140–164
    return "elite"                    # 165+


def main():
    cards = json.loads(SRC.read_text())

    token_index: dict      = defaultdict(list)
    by_element: dict       = defaultdict(list)
    by_set: dict           = defaultdict(list)
    by_treatment: dict     = defaultdict(list)
    by_card_type: dict     = defaultdict(list)
    by_hero: dict          = defaultdict(list)
    by_power_range: dict   = defaultdict(list)
    by_dbs_tier: dict      = defaultdict(list)
    by_hd_cost: dict       = defaultdict(list)
    by_play_subtype: dict  = defaultdict(list)
    has_image: list        = []
    by_release: dict       = defaultdict(list)

    for c in cards:
        bid = c.get("bobaId")
        if not bid:
            continue
        # Token index — feeds free-text search box.
        for tok in (c.get("searchTokens") or []):
            if tok:
                token_index[str(tok).lower()].append(bid)
        # Per-card search aliases — word-split each alias and add every
        # resulting token to the index. e.g. ["Skeeball", "Skee-Ball"]
        # → tokens "skeeball", "skee", "ball" all added (the prefix
        # match in CardSearch handles partial typing).
        for alias in (c.get("searchAliases") or []):
            if not alias:
                continue
            # Match CardSearch.wordSplit: lowercase + split on non-alnum.
            import re
            for tok in re.split(r"[^a-z0-9]+", str(alias).lower()):
                if tok:
                    token_index[tok].append(bid)
        # Facet indexes — drive the filter dropdowns.
        if c.get("element"):    by_element[c["element"]].append(bid)
        if c.get("set"):        by_set[c["set"]].append(bid)
        if c.get("treatment"):  by_treatment[c["treatment"]].append(bid)
        if c.get("cardType"):   by_card_type[c["cardType"]].append(bid)
        if c.get("hero") and c.get("cardType") == "Hero":
            by_hero[c["hero"]].append(bid)
        if c.get("release"):    by_release[c["release"]].append(bid)
        band = power_band(c.get("power"))
        if band:                by_power_range[band].append(bid)
        if c.get("dbsTier"):    by_dbs_tier[c["dbsTier"]].append(bid)
        if c.get("playCost") is not None and c.get("cardType") == "Play":
            by_hd_cost[str(c["playCost"])].append(bid)
        if c.get("cardType") == "Play":
            if c.get("isBonusPlay"):  by_play_subtype["BonusPlay"].append(bid)
            elif c.get("isHTD"):      by_play_subtype["HTD"].append(bid)
            else:                     by_play_subtype["Standard"].append(bid)
        if c.get("imageFile"):
            has_image.append(bid)

    out = {
        "tokenIndex":     {k: sorted(set(v)) for k, v in sorted(token_index.items())},
        "byElement":      {k: sorted(set(v)) for k, v in sorted(by_element.items())},
        "bySet":          {k: sorted(set(v)) for k, v in sorted(by_set.items())},
        "byTreatment":    {k: sorted(set(v)) for k, v in sorted(by_treatment.items())},
        "byCardType":     {k: sorted(set(v)) for k, v in sorted(by_card_type.items())},
        "byHero":         {k: sorted(set(v)) for k, v in sorted(by_hero.items())},
        "byPowerRange":   {k: sorted(set(v)) for k, v in sorted(by_power_range.items())},
        "byDbsTier":      {k: sorted(set(v)) for k, v in sorted(by_dbs_tier.items())},
        "byHdCost":       {k: sorted(set(v)) for k, v in sorted(by_hd_cost.items())},
        "byPlaySubtype":  {k: sorted(set(v)) for k, v in sorted(by_play_subtype.items())},
        "hasImage":       sorted(set(has_image)),
        "byRelease":      {k: sorted(set(v)) for k, v in sorted(by_release.items())},
    }
    DST.write_text(json.dumps(out, indent=2) + "\n")
    print(f"Wrote {DST}: {sum(len(v) for v in by_card_type.values())} cards indexed")


if __name__ == "__main__":
    main()
