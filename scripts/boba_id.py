#!/usr/bin/env python3
"""
boba_id.py — Canonical unique card identifier for BOBA Playbook.

Mantra: **One Image per Card. One ID per Card.**

Every card in the catalog must be uniquely identifiable by its `bobaId`.
This module is the single source of truth for the formula — every Cowork
script and every Claude Code script imports from here (or mirrors this
exact implementation) so the two sides never drift.

Formula
-------
    bobaId = "{cardNumber}-{hero||name}-{treatment??''}-{variation??''}-{element??''}"

Notes
-----
* `cardNumber` is required.
* `hero` is preferred; falls back to `name` for non-Hero cards (Plays,
  Hot Dogs, Sealed Products — all of which lack a hero field).
* `treatment`, `variation`, and `element` may be null; empty strings are
  used in the ID so trailing dashes are intentional and stable.
* The 5th field is the card's WEAPON (catalog field name `element` for
  legacy reasons — DECISIONS.md #027 — but the BoBA-canonical term is
  Weapon). Added 2026-05-25 after the audit pipeline revealed many
  Grandma's Linoleum Battlefoil cards exist as FIRE-weapon +
  GLOW-weapon siblings with otherwise-identical (hero, treatment,
  variation). The 4-field formula collided on those pairs, forcing the
  catalog to use distinct cardNumbers as a workaround (GLBF-43=GLOW,
  GLBF-85=FIRE). With weapon in the formula, the same printed
  cardNumber can be retained for both weapon variants.
* As of 2026-04-09 the 4-field formula produced 17,739 unique IDs
  across 17,739 cards (0 collisions). The 3-field formula had 3
  collisions on First Edition vs 2026 Edition variants — hence the
  addition of `variation`. The 5-field formula is forward-compatible
  for new weapon-only variants in future sets.

Usage
-----
    from boba_id import boba_id, build_boba_index
    bid = boba_id(card)
    idx = build_boba_index(cards)   # {bobaId: (list_index, card)}
"""

from typing import Dict, List, Tuple

__all__ = ["boba_id", "build_boba_index", "FORMULA"]

FORMULA = "{cardNumber}-{hero||name}-{treatment??''}-{variation??''}-{element??''}"


def boba_id(card: dict) -> str:
    """Compute the canonical bobaId for a card dict."""
    cn    = str(card.get("cardNumber") or "").strip()
    hero  = str(card.get("hero") or card.get("name") or "").strip()
    treat = str(card.get("treatment") or "").strip()
    var   = str(card.get("variation") or "").strip()
    elem  = str(card.get("element") or "").strip()
    return f"{cn}-{hero}-{treat}-{var}-{elem}"


def build_boba_index(cards: List[dict]) -> Dict[str, Tuple[int, dict]]:
    """Return {bobaId: (list_index, card)}. First occurrence wins on dupes.

    Also prints a warning to stderr if duplicates exist — a duplicate
    bobaId is a data quality bug that should be fixed in the catalog,
    not papered over.
    """
    import sys
    index: Dict[str, Tuple[int, dict]] = {}
    dupes: List[str] = []
    for i, c in enumerate(cards):
        bid = boba_id(c)
        if bid in index:
            dupes.append(bid)
        else:
            index[bid] = (i, c)
    if dupes:
        print(
            f"⚠ boba_id: {len(dupes)} duplicate bobaId(s) in catalog — "
            f"first occurrence wins. Sample: {dupes[:3]}",
            file=sys.stderr,
        )
    return index


if __name__ == "__main__":
    # Quick self-test against cards.json
    import json, sys
    from pathlib import Path

    p = Path(__file__).resolve().parent.parent / "unified-cards" / "data" / "cards.json"
    if not p.exists():
        # Try relative to BOBA-Playbook layout
        p = Path(__file__).resolve().parent.parent / "assets" / "data" / "cards.json"
    if not p.exists():
        sys.exit("cards.json not found in expected locations")

    cards = json.loads(p.read_text())
    if isinstance(cards, dict) and "cards" in cards:
        cards = cards["cards"]
    idx = build_boba_index(cards)
    print(f"cards: {len(cards):,}   unique bobaIds: {len(idx):,}")
    print(f"formula: {FORMULA}")
    print(f"sample:  {boba_id(cards[0])}")
