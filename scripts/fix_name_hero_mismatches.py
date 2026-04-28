#!/usr/bin/env python3
"""Fix `name`/`hero` mismatches across all card-catalog JSON bundles.

The `name` field is what surfaces in the UI; the `hero` field is the
canonical lookup key. Whenever `hero` differs from `name` on a Hero card
it's a data error (e.g. BBF-64 Wild Beard rendered as "Spider" because
sibling-data leaked into `name`).

Strategy:
- Hero / HotDog cards: align `name` to `hero`. If the value itself
  carries an obvious typo (e.g. "Pinch HItter") rewrite both to the
  canonical spelling.
- Plays: align `name` to `hero` EXCEPT for the Superfan Series Sandstorm
  Edition (SSE-20..29) reskins, which intentionally use a themed alt
  title in `name` distinct from the play's gameplay name in `hero`.
- Capitalization typos in the hero field itself get rewritten to the
  canonical Title Case used by the published checklists.
"""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Canonical rewrites for values that carry an obvious typo. Both `hero`
# and `name` are normalized to the value on the right whenever the value
# on the left appears in either field.
HERO_CANONICAL = {
    "Pinch HItter": "Pinch Hitter",
    "Hogeball": "Hoge-Ball",
    "Bern Baby,Bern": "Bern Baby, Bern",
    "BECKSy Birddog": "Becky Birddog",
}

# SSE Plays whose `name` is intentionally a themed alt-title and must
# NOT be normalized.
SSE_INTENTIONAL_ALT = {
    "SSE-20", "SSE-21", "SSE-22", "SSE-23", "SSE-24",
    "SSE-25", "SSE-26", "SSE-27", "SSE-28", "SSE-29",
}

BUNDLES = [
    "assets/data/cards.json",
    "assets/data/cards-slim.json",
    "assets/data/display-cards.json",
    "BOBAPlaybook/display-cards.json",
]


def fix(card: dict) -> bool:
    """Return True if the card was modified."""
    hero = card.get("hero")
    name = card.get("name")
    if not hero or not name or hero == name:
        return False
    cn = card.get("cardNumber") or ""
    if cn in SSE_INTENTIONAL_ALT:
        return False

    new_hero = HERO_CANONICAL.get(hero, hero)
    new_name = new_hero  # always align name to hero (post-canonical)

    changed = False
    if new_hero != hero:
        card["hero"] = new_hero
        changed = True
    if new_name != name:
        card["name"] = new_name
        changed = True
    return changed


def main():
    total_fixed = 0
    for rel in BUNDLES:
        path = ROOT / rel
        if not path.exists():
            print(f"skip (missing): {rel}")
            continue
        with path.open() as f:
            cards = json.load(f)
        fixed = sum(1 for c in cards if fix(c))
        path.write_text(json.dumps(cards, indent=2) + "\n")
        print(f"  {rel}: fixed {fixed} rows ({len(cards)} total)")
        total_fixed += fixed
    print(f"\nTotal fixed across all bundles: {total_fixed}")


if __name__ == "__main__":
    main()
