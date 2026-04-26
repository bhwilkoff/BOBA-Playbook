#!/usr/bin/env python3
"""Apply the power-realign patch produced by `build_power_patch.py`.

Reads `handoff-updates-2026-04-26/power-realign/patch.json`, applies
`modify[]` entries to the master cards.json (matching by `old_bobaId`),
copies the result into all 4 downstream bundles, and regenerates
`categories.json` + `search-index.json`.

Power changes don't alter bobaId (the formula is
`cardNumber-hero-treatment-variation`), so:
  - No R2 image renames
  - No Supabase row migration

This script reuses the categories + search-index builders from
`apply_hot_dog_handoff.py` by import. Idempotency: re-running after a
successful apply is a no-op (the catalog already has the new power, so
modify entries with `old_bobaId` will lookup-fail unless the bobaId is
still pre-rename — but power-realign doesn't rename bobaIds, so the
lookup always succeeds; the `changes` would just no-op rewrite the
same value).

Usage:
  python3 scripts/apply_power_realign.py \
    --patch handoff-updates-2026-04-26/power-realign/patch.json
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESEARCH = Path(
    "/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research"
)
MASTER_CARDS = RESEARCH / "unified-cards/data/cards.json"
WEB_CARDS = ROOT / "assets/data/cards.json"
WEB_CATEGORIES = ROOT / "assets/data/categories.json"
WEB_INDEX = ROOT / "assets/data/search-index.json"
IOS_DISPLAY = ROOT / "BOBAPlaybook/display-cards.json"
IOS_HEAD = ROOT / "BOBAPlaybook/cards-head.json"

# Reuse the (proven) categories + search-index builders.
sys.path.insert(0, str(ROOT / "scripts"))
from apply_hot_dog_handoff import build_categories, build_search_index  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--patch", required=True, type=Path)
    args = ap.parse_args()

    patch = json.loads(args.patch.read_text())
    print(f"Loaded patch: {len(patch.get('modify', []))} modify entries")
    print(f"Loading master: {MASTER_CARDS}")
    cards = json.loads(MASTER_CARDS.read_text())
    print(f"  baseline: {len(cards):,} cards")

    by_bobaId = {c.get("bobaId"): i for i, c in enumerate(cards) if c.get("bobaId")}

    applied = 0
    skipped = 0
    nochange = 0
    delta_hist: Counter = Counter()
    for action in patch.get("modify", []):
        old_bid = action["old_bobaId"]
        idx = by_bobaId.get(old_bid)
        if idx is None:
            skipped += 1
            print(f"  WARN: bobaId not found, skipped: {old_bid}")
            continue
        before = cards[idx].get("power")
        after = action["changes"].get("power")
        if before == after:
            nochange += 1
            continue
        cards[idx]["power"] = after
        if before is not None and after is not None:
            delta_hist[after - before] += 1
        applied += 1

    print(f"  applied: {applied}, no-change: {nochange}, skipped: {skipped}")
    if delta_hist:
        print("  power-delta histogram:")
        for d in sorted(delta_hist.keys()):
            print(f"    {d:+d} → {delta_hist[d]} rows")

    if applied == 0:
        print("Nothing to write. Exiting.")
        return

    print()
    print("Writing bundles…")
    master_text = json.dumps(cards, indent=2, ensure_ascii=False)
    MASTER_CARDS.write_text(master_text)
    print(f"  wrote {MASTER_CARDS}")
    WEB_CARDS.write_text(master_text)
    print(f"  wrote {WEB_CARDS}")
    IOS_DISPLAY.write_text(json.dumps(cards, ensure_ascii=False, separators=(",", ":")))
    print(f"  wrote {IOS_DISPLAY}")
    IOS_HEAD.write_text(json.dumps(cards[:500], ensure_ascii=False))
    print(f"  wrote {IOS_HEAD}")

    print("\nBuilding categories.json…")
    cats = build_categories(cards)
    WEB_CATEGORIES.write_text(json.dumps(cats, indent=2, ensure_ascii=False))
    print(f"  wrote {WEB_CATEGORIES}")

    print("\nBuilding search-index.json…")
    idx = build_search_index(cards)
    WEB_INDEX.write_text(json.dumps(idx, indent=2, ensure_ascii=False))
    print(f"  wrote {WEB_INDEX}")

    print("\nDone.")


if __name__ == "__main__":
    main()
