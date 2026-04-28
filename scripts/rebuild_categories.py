#!/usr/bin/env python3
"""Rebuild `assets/data/categories.json` from the master cards.json.

The categories file drives every filter dropdown on web + iOS. After
appending new records (e.g. the OKC Thunder World Champions set) the
filter UIs need to surface the new heroes / sub-sets / treatments.

This is a count-and-aggregate pass — no image optimization, no R2
work. It mirrors the shape of the existing categories.json so the
diff stays focused on the new additions.
"""
from __future__ import annotations
import json
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC  = ROOT / "assets/data/cards.json"
DST  = ROOT / "assets/data/categories.json"

# Element → community rarity tag, lifted from existing categories.json
# so the rebuild preserves the same labels.
ELEMENT_RARITY = {
    "FIRE":  "Common",
    "ICE":   "Rare SP",
    "STEEL": "Common",
    "BRAWL": "Common",
    "GLOW":  "Ultra Rare",
    "HEX":   "Super Ultra Rare",
    "GUM":   "Ultra Ultra Rare",
    "SUPER": "Mythic",
    "ALT":   "Champion Alt",
    "NONE":  "Non-weapon",
}


def main():
    cards = json.loads(SRC.read_text())

    sets:       dict = defaultdict(lambda: {"count": 0, "subSets": set(), "treatments": set()})
    treatments: dict = defaultdict(lambda: {"count": 0, "elements": set(), "sampleBobaIds": []})
    elements:   dict = defaultdict(lambda: {"count": 0})
    heroes:     dict = defaultdict(lambda: {"count": 0, "athletes": set(), "bobaIds": []})
    card_types: Counter = Counter()
    dbs_tiers:  Counter = Counter()
    hd_costs:   Counter = Counter()
    play_subs:  Counter = Counter()

    total_with_images = 0

    for c in cards:
        s   = c.get("set")
        ss  = c.get("subSet")
        tr  = c.get("treatment")
        el  = c.get("element")
        h   = c.get("hero")
        ai  = c.get("athleteInspiration")
        bid = c.get("bobaId")
        ct  = c.get("cardType")
        dt  = c.get("dbsTier")
        hc  = c.get("playCost")
        bp  = c.get("isBonusPlay")
        htd = c.get("isHTD")
        img = c.get("imageFile")

        if img:
            total_with_images += 1
        if s:
            sets[s]["count"] += 1
            if ss:  sets[s]["subSets"].add(ss)
            if tr:  sets[s]["treatments"].add(tr)
        if tr:
            treatments[tr]["count"] += 1
            if el: treatments[tr]["elements"].add(el)
            if bid and len(treatments[tr]["sampleBobaIds"]) < 5:
                treatments[tr]["sampleBobaIds"].append(bid)
        if el:
            elements[el]["count"] += 1
        # heroes dict is keyed off Hero cardType only — matches the
        # existing categories.json shape. Plays and HotDogs share the
        # `hero` field internally for lookup, but they don't surface in
        # the Hero filter facet on either platform.
        if h and ct == "Hero":
            heroes[h]["count"] += 1
            if ai: heroes[h]["athletes"].add(ai)
            if bid and len(heroes[h]["bobaIds"]) < 10:
                heroes[h]["bobaIds"].append(bid)
        if ct:
            card_types[ct] += 1
        if dt:
            dbs_tiers[dt] += 1
        if hc is not None and ct == "Play":
            hd_costs[str(hc)] += 1
        if ct == "Play":
            if bp:    play_subs["BonusPlay"] += 1
            elif htd: play_subs["HTD"]       += 1
            else:     play_subs["Standard"]  += 1

    # Stable serialization: sort sets/treatments/elements/heroes inside
    # each container so diffs against the previous categories.json
    # surface only meaningful changes.
    def materialize_set(s, k_sort=None):
        out = dict(s)
        for v in out.values():
            if "subSets" in v:    v["subSets"]    = sorted(v["subSets"])
            if "treatments" in v: v["treatments"] = sorted(v["treatments"])
            if "elements" in v:   v["elements"]   = sorted(v["elements"])
            if "athletes" in v:   v["athletes"]   = sorted(v["athletes"])
            if "bobaIds" in v:    v["bobaIds"]    = sorted(v["bobaIds"])
        return {k: out[k] for k in sorted(out.keys())}

    elements_out = {k: {"count": v["count"], "rarity": ELEMENT_RARITY.get(k, "Common")}
                    for k, v in sorted(elements.items())}

    out = {
        "sets":         materialize_set(sets),
        "treatments":   materialize_set(treatments),
        "elements":     elements_out,
        "heroes":       materialize_set(heroes),
        "cardTypes":    dict(card_types.most_common()),
        "dbsTiers":     dict(dbs_tiers.most_common()),
        "hdCosts":      {k: hd_costs[k] for k in sorted(hd_costs)},
        "playSubtypes": dict(play_subs.most_common()),
        "totalCards":      len(cards),
        "totalWithImages": total_with_images,
    }
    DST.write_text(json.dumps(out, indent=2) + "\n")
    print(f"Wrote {DST}: {len(cards)} cards, {len(heroes)} heroes, {total_with_images} with images")


if __name__ == "__main__":
    main()
