#!/usr/bin/env python3
"""
fix_skeee_weapons.py — apply the 8 Skeee weapon-rotation corrections
the audit agent identified on 2026-05-25.

CONTEXT
-------
The Skeee phantom-row investigation (memory:
reference_skeee_audit_2026_05_25) confirmed that all 27 Skeee rows
in the catalog are real BoBA cards per the official
bobattlearena.com/checklists/ database. BUT 8 of those rows carry
the wrong weapon. The catalog's RAD-* and GLBF-* Skeee assignments
use rotation [HEX, FIRE, STEEL, GLOW, ICE] for cardNumbers
[41, 83, 125, 167, 209]. The official rotation is
[HEX, GLOW, FIRE, ICE, STEEL]. The Mixtape Skeee rows already use
the correct rotation, proving this is set-specific upstream data
contamination, not a formula bug.

WHAT THIS DOES
--------------
For each of the 8 affected rows:
  1. Looks up the card by its current v3 bobaId
  2. Rewrites `element` to the official value
  3. Regenerates the bobaId (v3 formula has element as 5th field)
  4. Verifies no collision against any other catalog row
  5. Writes the updated catalog atomically

USAGE
-----
    python3 pipeline/scripts/fix_skeee_weapons.py --apply

Run without --apply for a dry-run.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


# (cardNumber, current_wrong_element, official_correct_element)
SKEEE_FIXES = [
    ("RAD-83",   "FIRE",  "GLOW"),
    ("RAD-125",  "STEEL", "FIRE"),
    ("RAD-167",  "GLOW",  "ICE"),
    ("RAD-209",  "ICE",   "STEEL"),
    ("GLBF-83",  "FIRE",  "GLOW"),
    ("GLBF-125", "STEEL", "FIRE"),
    ("GLBF-167", "GLOW",  "ICE"),
    ("GLBF-209", "ICE",   "STEEL"),
]


def build_boba_id(card: dict) -> str:
    cn = card.get("cardNumber") or ""
    hero = card.get("hero") or card.get("name") or ""
    treat = card.get("treatment") or ""
    var = card.get("variation") or ""
    elem = card.get("element") or ""
    return f"{cn}-{hero}-{treat}-{var}-{elem}"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--catalog", default="assets/data/cards.json")
    p.add_argument("--apply", action="store_true")
    args = p.parse_args()

    catalog_path = Path(args.catalog)
    cards = json.loads(catalog_path.read_text())
    print(f"[skeee-fix] catalog: {len(cards)} cards")

    by_boba = {c.get("bobaId"): c for c in cards if c.get("bobaId")}
    changes = []
    collisions = []

    for cardNumber, wrong_elem, correct_elem in SKEEE_FIXES:
        # Find the Skeee row at this cardNumber with the wrong-but-current element
        target = None
        for c in cards:
            if (c.get("cardNumber") == cardNumber
                    and c.get("hero") == "Skeee"
                    and c.get("element") == wrong_elem):
                target = c
                break
        if target is None:
            print(f"[skeee-fix] SKIP {cardNumber}: no Skeee row found with element={wrong_elem}")
            continue

        old_bid = target.get("bobaId")
        # Compute new bobaId with correct element
        hypothetical = dict(target)
        hypothetical["element"] = correct_elem
        new_bid = build_boba_id(hypothetical)

        # Collision check
        if new_bid in by_boba and by_boba[new_bid] is not target:
            collisions.append((old_bid, new_bid))
            continue

        changes.append((target, old_bid, new_bid, correct_elem))

    if collisions:
        print(f"\n[skeee-fix] ABORT — {len(collisions)} bobaId collisions:")
        for old, new in collisions:
            print(f"  {old}")
            print(f"  → {new}  (collision with existing row)")
        return 1

    print(f"\n[skeee-fix] {len(changes)} fixes ready:")
    for _card, old_bid, new_bid, new_elem in changes:
        print(f"  {old_bid}")
        print(f"  → {new_bid}  (element → {new_elem})")

    if not args.apply:
        print("\n[skeee-fix] DRY RUN — no writes. Re-run with --apply.")
        return 0

    for card, old_bid, new_bid, new_elem in changes:
        card["element"] = new_elem
        card["bobaId"] = new_bid

    tmp = catalog_path.with_suffix(catalog_path.suffix + ".tmp")
    tmp.write_text(json.dumps(cards, indent=2, ensure_ascii=True) + "\n")
    tmp.replace(catalog_path)
    print(f"\n[skeee-fix] WROTE {catalog_path} — {len(changes)} Skeee weapons corrected.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
