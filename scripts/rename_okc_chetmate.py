#!/usr/bin/env python3
"""Rename OKC's `Chetmate` records to `ChetMate` so the new World
Champions Debut prints share a hero name (and bobaId stem) with the
46 pre-existing Alpha-edition ChetMate records.

User confirmed (2026-04-28): "Use ChetMate, as this is just a new
version of the same hero." Cowork's handoff CSV used the
checklist's "Chetmate" spelling, but the catalog has carried
"ChetMate" since the Alpha edition. Aligning the OKC additions to
the existing CamelCase keeps the hero filter, byHero search index,
and the rainbow view (which groups by hero name) consolidated to a
single ChetMate row.

Safe to rename freely — these 6 bobaIds were authored yesterday
and have not yet been written to any user_cards row in Supabase,
so changing the bobaId string here doesn't orphan user data.
"""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUNDLES = [
    "assets/data/cards.json",
    "assets/data/cards-slim.json",
    "assets/data/display-cards.json",
    "BOBAPlaybook/display-cards.json",
]


def main():
    total = 0
    for rel in BUNDLES:
        path = ROOT / rel
        if not path.exists():
            print(f"  skip (missing): {rel}")
            continue
        cards = json.loads(path.read_text())
        renamed = 0
        for c in cards:
            if c.get("hero") == "Chetmate":
                c["hero"] = "ChetMate"
                if c.get("name") == "Chetmate":
                    c["name"] = "ChetMate"
                bid = c.get("bobaId")
                if bid and "-Chetmate-" in bid:
                    c["bobaId"] = bid.replace("-Chetmate-", "-ChetMate-")
                # searchTokens are lowercased — token "chetmate" stays the
                # same regardless of casing on the source field, so no
                # changes there.
                renamed += 1
        path.write_text(json.dumps(cards, indent=2) + "\n")
        print(f"  {rel}: renamed {renamed}")
        total += renamed
    print(f"\nTotal records renamed: {total}")


if __name__ == "__main__":
    main()
