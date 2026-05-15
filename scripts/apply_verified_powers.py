#!/usr/bin/env python3
"""
apply_verified_powers.py — repair card power values by reading the
TRUTH off each card's image, not by guessing from sibling-mode.

Supersedes scripts/fix_invalid_powers.py from v2.222, which used
sibling-mode fallback and got 23 of 30 records wrong (some heroes
have different power values across treatments, so "most common
power for this hero" is a bad heuristic).

The values below were read by viewing each card's R2 image
directly. Every value matches the printed power top-right of the
card art.

Usage: `python scripts/apply_verified_powers.py [--apply]`.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

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

# Truth table — power value read directly off each card's R2 image.
# bobaId → printed-power.
TRUTH: dict[str, int] = {
    "BFA-3-Emmitt-164-Inspired Ink Battlefoil-Emmitt Smith Debut":             200,
    "BFA-130-Howietzer-Inspired Ink Battlefoil-Howie Long Debut":              165,
    "BHBF-60-Sarrtillery-Blue Headlines Battlefoil-First Edition":              90,
    "CHILL-20-Bags-Chillin' Battlefoil-Jeff Bagwell Debut":                    165,
    "CYB-13-Emmitt-164-Cyber-2025 Cyber Promo":                                140,
    "FT-91-Botto-Fire Tracks Battlefoil-First Edition":                         95,
    "FT-127-Forcefield-Fire Tracks Battlefoil-First Edition":                   90,
    "GGL-455-Game Over-Great Grandma's Linoleum Battlefoil-Éric Gagné Debut":  140,
    "GGL-526-The Kid-Great Grandma's Linoleum Battlefoil-Cover Hero":          185,
    "IBF-193-Action-Icon Battlefoil-2026 Edition":                              90,
    "IBF-194-Go-Cart-Icon Battlefoil-First Edition":                            90,
    "IBF-367-JacHammer-Icon Battlefoil-First Edition":                          90,
    "MBFA-2-Emmitt-164-Inspired Ink Metallic Battlefoil-Emmitt Smith Debut":   170,
    "MI-3-Emmitt-164-Miami Ice Battlefoil-Emmitt Smith Debut":                 185,
    "MIX-760-Courthouse-Mixtape Battlefoil-First Edition":                      95,
    "MIX-763-JacHammer-Mixtape Battlefoil-First Edition":                       90,
    "MIX-764-BaldWing-Mixtape Battlefoil-First Edition":                        90,
    "MIX-766-Camera-Mixtape Battlefoil-First Edition":                          90,
    "MIX-767-Homestead-Mixtape Battlefoil-First Edition":                       90,
    "MIX-768-Scary-Mixtape Battlefoil-First Edition":                           90,
    "OBF-101-Risarcher-Orange Battlefoil-First Edition":                        90,
    "OBF-127-Forcefield-Orange Battlefoil-First Edition":                       90,
    "PG-110-Rook-Power Glove Battlefoil-First Edition":                         90,
    "PG-111-Camera-Power Glove Battlefoil-First Edition":                       90,
    "PG-125-Bell-Camp-Power Glove Battlefoil-First Edition":                    80,
    "RBF-121-Lumber-Red Battlefoil-First Edition":                              80,
    "RBF-125-Bell-Camp-Red Battlefoil-First Edition":                           80,
    "SBF-121-Lumber-Silver Battlefoil-First Edition":                           90,
    "SRA-6-Rollin'-Inspired Ink Battlefoil-Scott Rolen Debut":                 140,
    "SSE-18-Hitstick-Paper & Battlefoil-Sandstorm Edition":                    130,
}


def rebuild_search_tokens(card: dict) -> str:
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


def patch_bundle(path: Path, dry_run: bool) -> tuple[int, int]:
    """Return (patched_now, already_correct)."""
    if not path.exists():
        return (0, 0)
    data = json.loads(path.read_text())
    cards = data["cards"] if isinstance(data, dict) and "cards" in data else data
    patched = 0
    already = 0
    for c in cards:
        bid = c.get("bobaId") or boba_id(c)
        if bid in TRUTH:
            want = TRUTH[bid]
            if c.get("power") == want:
                already += 1
            else:
                c["power"] = want
                if "searchTokens" in c:
                    c["searchTokens"] = rebuild_search_tokens(c)
                patched += 1
    if not dry_run and patched > 0:
        path.write_text(json.dumps(data if isinstance(data, dict) and "cards" in data else cards,
                                   ensure_ascii=False, indent=2) + "\n")
    return (patched, already)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="Write bundles (omit for dry-run).")
    args = ap.parse_args()
    dry = not args.apply

    cards_path = REPO / "assets" / "data" / "cards.json"
    catalog = {(c.get("bobaId") or boba_id(c)): c for c in json.loads(cards_path.read_text())}

    print(f"{'bobaId':75s}  {'current':>7s} → {'truth':>5s}")
    print("-" * 100)
    for bid, want in TRUTH.items():
        cur = catalog.get(bid, {}).get("power")
        marker = "✓" if cur == want else "•"
        print(f"{bid!r:75s}  {str(cur):>7s} → {want:>5d}  {marker}")
    print()

    if dry:
        print(f"DRY RUN: {len(TRUTH)} verified values. Run with --apply to commit.")
        return

    for path in BUNDLES:
        patched, already = patch_bundle(path, dry_run=False)
        print(f"  {path.name}: patched {patched}, already-correct {already}")

    print(f"\nDone. {len(TRUTH)} card(s) processed.")


if __name__ == "__main__":
    main()
