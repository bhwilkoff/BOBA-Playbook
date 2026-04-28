#!/usr/bin/env python3
"""Apply the OKC Thunder World Champions handoff to every catalog
bundle. Source of truth lives at
`handoff-updates-2026-04-27/okc-world-champions/cards-add.json`.

The handoff adds 54 new records (36 Heroes + 10 Plays + 8 Hot Dogs)
to the World Champions set. All `imageFile` values are null on author —
image sourcing is a separate pass. bobaId formula remains canonical
(scripts/boba_id.py) and was verified collision-free against the
existing 17,914-row catalog.

Mirrors the manual steps from COWORK_OKC_HANDOFF.md so the next
person who needs to roll the same shape (e.g. an OKC-supplement DBS
patch later, or another team's World Champions checklist) can
duplicate the script with minimal edits.
"""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HANDOFF = ROOT / "handoff-updates-2026-04-27/okc-world-champions/cards-add.json"

# Master + downstream bundles per CLAUDE.md mantra. cards-head.json is
# only the first 500 records and serves the iOS instant-first-frame —
# OKC sits well past row 500 so head needs no update. Same goes for
# the web cards-head.json.
BUNDLES = [
    "assets/data/cards.json",
    "assets/data/cards-slim.json",
    "assets/data/display-cards.json",
    "BOBAPlaybook/display-cards.json",
]


def main():
    handoff = json.loads(HANDOFF.read_text())
    rows = handoff.get("rows", [])
    if not rows:
        raise SystemExit("No rows in handoff cards-add.json")

    # _authorNote is informational provenance — strip it out of the
    # shipped catalog. Keeps the stored shape identical to other rows.
    cleaned = []
    for r in rows:
        r = dict(r)
        r.pop("_authorNote", None)
        cleaned.append(r)

    new_bids = {r["bobaId"] for r in cleaned}
    print(f"OKC handoff: {len(cleaned)} new records ({len(new_bids)} unique bobaIds)")

    for rel in BUNDLES:
        path = ROOT / rel
        if not path.exists():
            print(f"  skip (missing): {rel}")
            continue
        cards = json.loads(path.read_text())
        existing = {c.get("bobaId") for c in cards}
        collisions = new_bids & existing
        if collisions:
            raise SystemExit(f"  COLLISION in {rel}: {sorted(collisions)[:5]}")
        before = len(cards)
        cards.extend(cleaned)
        after = len(cards)
        path.write_text(json.dumps(cards, indent=2) + "\n")
        print(f"  {rel}: {before} → {after}")

    print("\nNext steps:")
    print("  - Regenerate categories.json + search-index.json (categories")
    print("    will pick up the new subSet '2025 - OKC Thunder' automatically).")
    print("  - When OKC art lands on R2, set imageFile / imageSource /")
    print("    imageAvailable on each row and rerun this script with a")
    print("    refreshed cards-add.json.")


if __name__ == "__main__":
    main()
