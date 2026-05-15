#!/usr/bin/env python3
"""
fix_invalid_powers.py — repair card power values that aren't multiples of 5.

A BoBA card's printed power is always a multiple of 5 (the lowest is
75, the highest in the catalog is ≥ 200 — all end in 0 or 5). The
Stage A→B→C image-recognition pipeline occasionally over-eagerly
picks a 3-digit number off the card art (a card-number-style "164",
or a misread of the actual power digits) and writes it into the
catalog's `power` field. A beta tester flagged this on multiple
Emmitt-164 cards (power=164) — the obvious-impossible value is the
red flag.

For each card with power % 5 != 0:

  1. Find sibling cards with the SAME hero AND SAME treatment that
     have a valid (multiple-of-5) power. Most-common value among
     those = canonical power.
  2. If no treatment-siblings exist, fall back to siblings with the
     SAME hero (any treatment).
  3. Patch the bad record's `power` and re-stamp searchTokens (the
     concatenated lookup string includes power as one token).
  4. Patch ALL FIVE catalog bundles in lockstep:
       assets/data/cards.json
       assets/data/cards-slim.json
       assets/data/cards-head.json
       BOBAPlaybook/display-cards.json
       BOBAPlaybook/cards-head.json

The hero name field is NOT modified, even when it looks suspicious
(e.g. "Emmitt-164" — that IS the correct hero name per BoBA).

USAGE
─────
    python scripts/fix_invalid_powers.py             # dry-run preview
    python scripts/fix_invalid_powers.py --apply     # writes bundles
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Optional

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))
from boba_id import boba_id  # noqa: E402

BUNDLES: list[Path] = [
    REPO / "assets" / "data" / "cards.json",
    REPO / "assets" / "data" / "cards-slim.json",
    REPO / "assets" / "data" / "cards-head.json",
    REPO / "BOBAPlaybook" / "display-cards.json",
    REPO / "BOBAPlaybook" / "cards-head.json",
]


def find_canonical_power(card: dict, catalog: list[dict]) -> Optional[int]:
    """Return the canonical power for `card` — most common power among
    same-hero same-treatment siblings, falling back to same-hero siblings."""
    hero = card.get("hero")
    treatment = card.get("treatment")
    own_bid = card.get("bobaId") or boba_id(card)

    def good(s: dict) -> bool:
        p = s.get("power")
        return (
            s.get("hero") == hero
            and s.get("cardType") == "Hero"
            and p is not None
            and p % 5 == 0
            and (s.get("bobaId") or boba_id(s)) != own_bid
        )

    # By treatment first — most specific match.
    siblings_treat = [s for s in catalog if good(s) and s.get("treatment") == treatment]
    if siblings_treat:
        return Counter(s["power"] for s in siblings_treat).most_common(1)[0][0]

    # By hero only — broader fallback.
    siblings_hero = [s for s in catalog if good(s)]
    if siblings_hero:
        return Counter(s["power"] for s in siblings_hero).most_common(1)[0][0]

    return None


def rebuild_search_tokens(card: dict) -> str:
    """Mirror the searchTokens shape used by import_new_cards.py."""
    bits = [
        card.get("hero", ""),
        card.get("name", ""),
        card.get("cardNumber", ""),
        card.get("set", ""),
        card.get("subSet") or "",
        card.get("treatment") or "",
        card.get("variation") or "",
        card.get("athleteInspiration") or "",
        card.get("element", ""),
        str(card.get("power")) if card.get("power") is not None else "",
    ]
    return " ".join(b for b in bits if b).lower()


def apply_to_bundle(path: Path, fixes: dict[str, int], dry_run: bool) -> int:
    """Patch each card by bobaId. Returns the count of records patched."""
    if not path.exists():
        print(f"  skip {path.name}: not present")
        return 0
    data = json.loads(path.read_text())
    cards = data["cards"] if isinstance(data, dict) and "cards" in data else data

    patched = 0
    for c in cards:
        bid = c.get("bobaId") or boba_id(c)
        if bid in fixes:
            c["power"] = fixes[bid]
            # Some bundles carry searchTokens; keep it in sync.
            if "searchTokens" in c:
                c["searchTokens"] = rebuild_search_tokens(c)
            patched += 1
    if not dry_run and patched > 0:
        path.write_text(json.dumps(data if isinstance(data, dict) and "cards" in data else cards,
                                   ensure_ascii=False, indent=2) + "\n")
    return patched


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="Write bundles (omit for dry-run)")
    args = ap.parse_args()
    dry = not args.apply

    cards_path = REPO / "assets" / "data" / "cards.json"
    catalog = json.loads(cards_path.read_text())

    bad = [c for c in catalog if c.get("power") is not None and c["power"] % 5 != 0]
    print(f"Found {len(bad)} cards with invalid power (not a multiple of 5).\n")

    fixes: dict[str, int] = {}
    unresolved: list[tuple[str, int]] = []
    print(f"{'bobaId':75s}  {'before':>6s}  →  {'after':>5s}")
    print("-" * 100)
    for c in bad:
        bid = c.get("bobaId") or boba_id(c)
        canon = find_canonical_power(c, catalog)
        if canon is None:
            unresolved.append((bid, c["power"]))
            print(f"{bid!r:75s}  {c['power']:>6d}  →  (no fix found)")
            continue
        fixes[bid] = canon
        print(f"{bid!r:75s}  {c['power']:>6d}  →  {canon:>5d}")

    print()
    if unresolved:
        print(f"⚠ Could not auto-resolve {len(unresolved)} card(s): {unresolved}")
        print()

    if dry:
        print(f"DRY RUN: would patch {len(fixes)} card(s) across {len(BUNDLES)} bundle(s).")
        print("Run with --apply to commit.")
        return

    for path in BUNDLES:
        n = apply_to_bundle(path, fixes, dry_run=False)
        print(f"  {path.name}: patched {n}")

    print(f"\nDone. Fixed {len(fixes)} record(s).")


if __name__ == "__main__":
    main()
