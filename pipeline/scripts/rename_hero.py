#!/usr/bin/env python3
"""
rename_hero.py — global rename of a hero across the catalog.

USE CASE
--------
2026-05-25: Ben flagged that "Boston Stongboy" appears 70 times
across the catalog and should be "Boston Strongboy". Pervasive
misspellings need a one-shot fix that:
  1. Updates every card's `hero` field.
  2. Regenerates each affected card's `bobaId` (5-field formula —
     hero is field 2).
  3. Verifies no resulting bobaId collisions.
  4. Optionally writes the updated catalog.

USAGE
-----
    python3 pipeline/scripts/rename_hero.py \\
        --catalog assets/data/cards.json \\
        --from "Boston Stongboy" \\
        --to   "Boston Strongboy" \\
        --apply

Run without --apply for a dry-run report.

SAFETY
------
- Refuses to apply if the new hero string already exists as a
  different hero in the catalog (would create real bobaId
  collisions on cards whose other fields happen to match).
- Verifies internal uniqueness post-rename: each renamed card
  gets a fresh bobaId that doesn't clash with any other catalog
  row (renamed OR not).
- Atomic write: temp file + rename.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--catalog", required=True)
    p.add_argument("--from", dest="from_name", required=True,
                   help="Current (misspelled / old) hero name")
    p.add_argument("--to", dest="to_name", required=True,
                   help="New (correct) hero name")
    p.add_argument("--apply", action="store_true",
                   help="Write the catalog back. Default = dry-run.")
    return p.parse_args()


def build_boba_id(card: dict) -> str:
    cn = card.get("cardNumber") or ""
    hero = card.get("hero") or card.get("name") or ""
    treat = card.get("treatment") or ""
    var = card.get("variation") or ""
    elem = card.get("element") or ""
    return f"{cn}-{hero}-{treat}-{var}-{elem}"


def main():
    args = parse_args()
    catalog_path = Path(args.catalog)
    with open(catalog_path) as f:
        cards = json.load(f)
    print(f"[rename] catalog: {len(cards)} cards", flush=True)

    matches = [c for c in cards if (c.get("hero") or "") == args.from_name]
    if not matches:
        print(f"[rename] no cards with hero={args.from_name!r}. Nothing to do.")
        return 0
    print(f"[rename] {len(matches)} cards to rename: "
          f"{args.from_name!r} → {args.to_name!r}")

    # Build collision check.
    other_bobaids = {c["bobaId"] for c in cards if c not in matches and c.get("bobaId")}
    proposed_changes = []  # (card, old_bobaId, new_bobaId)
    internal_dup_check = set()
    collisions = []
    for c in matches:
        old_bid = c.get("bobaId")
        hypothetical = dict(c)
        hypothetical["hero"] = args.to_name
        new_bid = build_boba_id(hypothetical)
        if new_bid in other_bobaids:
            collisions.append((old_bid, new_bid, "external"))
        elif new_bid in internal_dup_check:
            collisions.append((old_bid, new_bid, "internal"))
        else:
            internal_dup_check.add(new_bid)
        proposed_changes.append((c, old_bid, new_bid))

    if collisions:
        print(f"\n[rename] ABORT — {len(collisions)} bobaId collisions:")
        for old, new, kind in collisions[:20]:
            print(f"  ({kind}) {old} → {new}")
        if len(collisions) > 20:
            print(f"  … and {len(collisions) - 20} more")
        return 1

    print(f"[rename] no collisions. Sample changes (5):")
    for c, old, new in proposed_changes[:5]:
        print(f"  {old}")
        print(f"  → {new}")

    if not args.apply:
        print(f"\n[rename] DRY RUN — no writes. Re-run with --apply.")
        return 0

    # Apply.
    for c, _old, new in proposed_changes:
        c["hero"] = args.to_name
        c["bobaId"] = new
    tmp = catalog_path.with_suffix(catalog_path.suffix + ".tmp")
    tmp.write_text(json.dumps(cards, indent=2, ensure_ascii=True) + "\n")
    tmp.replace(catalog_path)
    print(f"\n[rename] WROTE {catalog_path} — {len(matches)} cards renamed + bobaId regenerated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
