#!/usr/bin/env python3
"""
backfill_null_athletes.py — eliminate `athleteInspiration: null` from the catalog.

Per user directive (2026-04-21): null is not an acceptable value for
`athleteInspiration`. Two cases:

1. Plays / HotDogs / Sealed Products — no real-world athlete applies.
   Backfill with "N/A" (explicit Not Applicable, filterable).
2. Heroes — every Hero is inspired by a real athlete (or a fictional BOBA
   character). For each null-athlete Hero row, look up the canonical athlete
   from other catalog records of the same hero. If no existing record has an
   athlete, mark "N/A" (fictional character with no real-world inspiration).

Writes the research-project cards.json, runs reconcile_all.py step 5/6/8/9,
and syncs the regenerated bundles into the BOBA-Playbook repo.
"""

import json
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path

APP_REPO = Path(__file__).resolve().parent.parent
RESEARCH = Path("/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research")
R_DATA   = RESEARCH / "unified-cards" / "data"
R_CARDS  = R_DATA / "cards.json"
APP_DATA = APP_REPO / "assets" / "data"
APP_IOS  = APP_REPO / "BOBAPlaybook"

NA = "N/A"

def canonical_athlete_by_hero(cards: list) -> dict[str, str]:
    """Build {hero_name_lower → most-common non-null athleteInspiration}.
    Case-insensitive so typos like Bojax/BoJax collapse together."""
    groups: dict[str, Counter] = {}
    for c in cards:
        hero = c.get("hero")
        ath  = c.get("athleteInspiration")
        if not hero or not ath:
            continue
        groups.setdefault(hero.lower(), Counter())[ath] += 1
    return {h: cnt.most_common(1)[0][0] for h, cnt in groups.items()}

def main():
    cards = json.loads(R_CARDS.read_text())
    before = sum(1 for c in cards if c.get("athleteInspiration") is None)
    print(f"Before: {before} rows with null athleteInspiration")

    athlete_by_hero = canonical_athlete_by_hero(cards)

    filled_from_catalog = 0    # Hero backfilled from existing catalog record
    filled_na_type      = 0    # Play/HotDog/SealedProduct → N/A
    filled_na_hero      = 0    # Hero with no catalog-canonical athlete → N/A

    fiction_heroes: list[str] = []    # Heroes that ended up as N/A
    derived_log: Counter = Counter()  # hero → athlete mappings applied

    for c in cards:
        if c.get("athleteInspiration") is not None:
            continue
        ct = c.get("cardType")
        if ct in ("Play", "HotDog", "Sealed Product"):
            c["athleteInspiration"] = NA
            filled_na_type += 1
        elif ct == "Hero":
            hero = (c.get("hero") or "").lower()
            canon = athlete_by_hero.get(hero)
            if canon:
                c["athleteInspiration"] = canon
                filled_from_catalog += 1
                derived_log[(c.get("hero"), canon)] += 1
            else:
                c["athleteInspiration"] = NA
                filled_na_hero += 1
                fiction_heroes.append(c.get("hero"))
        else:
            c["athleteInspiration"] = NA
            filled_na_type += 1

    after = sum(1 for c in cards if c.get("athleteInspiration") is None)
    print(f"After:  {after} rows with null athleteInspiration")
    print(f"  Heroes backfilled from catalog: {filled_from_catalog}")
    print(f"  Heroes marked N/A (fictional):  {filled_na_hero}  → {sorted(set(fiction_heroes))}")
    print(f"  Plays/HotDogs/Sealed → N/A:     {filled_na_type}")
    print()
    print("Sample Hero backfills:")
    for (hero, athlete), n in derived_log.most_common(10):
        print(f"  {hero:<24} → {athlete}  ({n} rows)")

    R_CARDS.write_text(json.dumps(cards, indent=2, ensure_ascii=False))

    # ─── Regenerate downstream bundles ────────────────────────────
    print("\nRegenerating bundles via reconcile_all.py …")
    for step in (5, 6, 8, 9):
        res = subprocess.run(
            [sys.executable, "reconcile_all.py", "--step", str(step)],
            cwd=RESEARCH, capture_output=True, text=True,
        )
        if res.returncode != 0:
            print(res.stdout); print(res.stderr, file=sys.stderr)
            raise RuntimeError(f"reconcile_all.py --step {step} failed")
        print(f"  --step {step} ✓")

    # ─── Sync bundles to BOBA-Playbook ────────────────────────────
    print("\nSyncing bundles to BOBA-Playbook repo …")
    for name in ("cards.json", "cards-slim.json", "categories.json",
                 "search-index.json", "missing-cards.json"):
        src, dst = R_DATA / name, APP_DATA / name
        if src.exists():
            shutil.copy2(src, dst)
            print(f"  {name}: {dst.stat().st_size:,} bytes")

    cards_app = json.loads((APP_DATA / "cards.json").read_text())
    # Sealed products stay in the iOS bundle (reversed 2026-04-22).
    display = cards_app
    head = display[:500]
    (APP_IOS / "display-cards.json").write_text(
        json.dumps(display, separators=(", ", ": "), ensure_ascii=False))
    (APP_IOS / "cards-head.json").write_text(
        json.dumps(head, separators=(", ", ": "), ensure_ascii=False))
    print(f"  display-cards.json: {len(display):,} cards")
    print(f"  cards-head.json: {len(head):,} cards")

    print("\n✓ Done.")

if __name__ == "__main__":
    main()
