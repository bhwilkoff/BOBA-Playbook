#!/usr/bin/env python3
"""Apply Cowork's 2026-04-27 rookie-inspired patch to every catalog
bundle.

The patch sets a new `rookieInspired: bool` field on every Hero
record. 2,733 rows go True, 14,502 go False. No bobaId churn, no R2
renames, no Supabase migration — pure additive schema enrichment.

What it does:
  1. md5-verifies the patch against the sidecar
  2. Loads master cards.json, applies modify[] entries via old_bobaId
     lookup
  3. Mirrors to all 4 downstream bundles (web cards, iOS display,
     iOS head, web search-index regen)
  4. Regenerates categories.json + search-index.json (the showcase
     filter doesn't depend on the search index, but keeping it in
     sync prevents future drift)

Usage:
  python3 scripts/apply_rookie_inspired.py
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESEARCH = Path(
    "/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research"
)
HANDOFF = RESEARCH / "handoff-updates-2026-04-27/rookie-inspired"
PATCH = HANDOFF / "patch.json"
PATCH_MD5 = HANDOFF / "patch.json.md5"

MASTER_CARDS = RESEARCH / "unified-cards/data/cards.json"
WEB_CARDS = ROOT / "assets/data/cards.json"
WEB_CATEGORIES = ROOT / "assets/data/categories.json"
WEB_INDEX = ROOT / "assets/data/search-index.json"
IOS_DISPLAY = ROOT / "BOBAPlaybook/display-cards.json"
IOS_HEAD = ROOT / "BOBAPlaybook/cards-head.json"

sys.path.insert(0, str(ROOT / "scripts"))
from apply_hot_dog_handoff import build_categories, build_search_index


def main() -> None:
    # md5 wire-check.
    expected = PATCH_MD5.read_text().split()[0]
    actual = hashlib.md5(PATCH.read_bytes()).hexdigest()
    if expected != actual:
        raise SystemExit(f"md5 mismatch: expected {expected}, got {actual}")
    print(f"Patch md5 verified: {actual}")

    patch = json.loads(PATCH.read_text())
    print(f"Patch entries: {len(patch.get('modify', []))}")

    cards = json.loads(MASTER_CARDS.read_text())
    print(f"Master baseline: {len(cards)} cards")
    by_bid = {c.get("bobaId"): i for i, c in enumerate(cards) if c.get("bobaId")}

    applied = 0
    skipped = 0
    for action in patch.get("modify", []):
        idx = by_bid.get(action["old_bobaId"])
        if idx is None:
            skipped += 1
            continue
        cards[idx].update(action["changes"])
        applied += 1

    print(f"  applied: {applied}, skipped: {skipped}")
    n_true = sum(1 for c in cards if c.get("rookieInspired") is True)
    n_false = sum(1 for c in cards if c.get("rookieInspired") is False)
    print(f"  rookieInspired = True:  {n_true}")
    print(f"  rookieInspired = False: {n_false}")

    print("\nWriting bundles…")
    master_text = json.dumps(cards, indent=2, ensure_ascii=False)
    MASTER_CARDS.write_text(master_text)
    WEB_CARDS.write_text(master_text)
    IOS_DISPLAY.write_text(json.dumps(cards, ensure_ascii=False, separators=(",", ":")))
    IOS_HEAD.write_text(json.dumps(cards[:500], ensure_ascii=False))
    print(f"  wrote {MASTER_CARDS}")
    print(f"  wrote {WEB_CARDS}")
    print(f"  wrote {IOS_DISPLAY}")
    print(f"  wrote {IOS_HEAD}")

    print("\nRegenerating categories.json + search-index.json…")
    cats = build_categories(cards)
    WEB_CATEGORIES.write_text(json.dumps(cats, indent=2, ensure_ascii=False))
    idx = build_search_index(cards)
    WEB_INDEX.write_text(json.dumps(idx, indent=2, ensure_ascii=False))
    print(f"  wrote {WEB_CATEGORIES}")
    print(f"  wrote {WEB_INDEX}")
    print("\nDone.")


if __name__ == "__main__":
    main()
