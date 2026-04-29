#!/usr/bin/env python3
"""Replace duplicate Play names in `assets/data/template-decks.json`
with unique plays from the catalog.

The 2026 Nationals deckbuilding rule states: "Exactly 30 Plays, all
unique names." Bonus Plays (gold-treatment) are extras and don't
count against the 30 — but the standard 30 must be unique. The
authored starters all carried duplicates (No Huddle ×3, Waiver Wire
Pickup ×2 in every deck, plus theme-specific repeats) which lit up
the deck-builder's duplicate warnings every time a coach loaded a
starter.

Strategy: per template, keep the first occurrence of each unique
play name. For every duplicate slot, swap in a play (by name) that
isn't already in the deck. Picker preference order:
  1. A play whose category/effect matches the template's theme
     (we approximate via simple keyword bands per template id).
  2. Any other Play in the catalog that's still unused.
This keeps the deck mechanically coherent with its archetype
without requiring per-play authoring.
"""
from __future__ import annotations
import json
from pathlib import Path
from collections import OrderedDict

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = ROOT / "assets/data/template-decks.json"
IOS_TEMPLATES = ROOT / "BOBAPlaybook/TemplateDeck.json"
CARDS = ROOT / "assets/data/cards.json"

# Theme keywords per template — used to bias the duplicate-replacement
# picker toward plays that read as "on-theme" for the archetype.
# Drawn from the play `category` and free-text matches against
# `playAbility`. Order matters within each list — first hit wins.
THEME_KEYWORDS = {
    "lockdown-locker":  ["steel", "lockout", "block", "deny", "discard", "draw"],
    "frozen-tempo":     ["ice", "substitut", "frost", "freeze", "draw"],
    "draw-and-adapt":   ["draw", "peek", "reorder", "search", "look at", "reveal"],
    "glow-sacrifice":   ["glow", "discard", "shuffle", "recover", "bonus play"],
    "brawl-beatdown":   ["brawl", "fire", "+", "power", "boost", "burn"],
}


def main():
    templates = json.loads(TEMPLATES.read_text())
    cards     = json.loads(CARDS.read_text())
    by_bid: dict[str, dict] = {c["bobaId"]: c for c in cards if c.get("bobaId")}

    # Build a pool of every Play card in the catalog, grouped by name.
    # The pool excludes Bonus Plays so we don't accidentally pad the
    # standard 30 with a Bonus (which would breakdeckbuild legality
    # under formats that disallow Bonus in the standard slots).
    all_plays_by_name: dict[str, list[dict]] = {}
    for c in cards:
        if c.get("cardType") != "Play":           continue
        if c.get("isBonusPlay"):                  continue
        name = c.get("hero") or c.get("name")
        if not name:                              continue
        all_plays_by_name.setdefault(name, []).append(c)

    total_swaps = 0
    for tid, t in templates.items():
        plays = list(t.get("playIds", []))

        # Pass 1: keep first occurrence of each name; collect dup slots.
        seen_names: set[str] = set()
        kept: list[str] = []
        dup_slots = 0
        for bid in plays:
            card = by_bid.get(bid)
            if not card:
                kept.append(bid)
                continue
            name = card.get("hero") or card.get("name")
            if name in seen_names:
                dup_slots += 1
                continue
            seen_names.add(name)
            kept.append(bid)

        if dup_slots == 0:
            print(f"  {tid}: already unique ({len(plays)} plays)")
            continue

        # Pass 2: for each dup slot, pick a unique replacement. Prefer
        # an on-theme name; fall back to any unused name.
        keywords = THEME_KEYWORDS.get(tid, [])
        candidates_by_name = {n: cs for n, cs in all_plays_by_name.items()
                              if n not in seen_names}
        # Score by theme keyword match — name-level score, since one
        # name = one play across all printings.
        def score(name: str) -> int:
            sample = candidates_by_name[name][0]
            blob = " ".join([
                name,
                sample.get("playAbility")  or "",
                sample.get("category")     or "",
            ]).lower()
            for i, kw in enumerate(keywords):
                if kw in blob:
                    return len(keywords) - i  # earlier kw = higher score
            return 0
        ranked_names = sorted(candidates_by_name.keys(),
                              key=lambda n: (-score(n), n))

        replacements: list[str] = []
        for name in ranked_names[:dup_slots]:
            # Prefer a "Plays" treatment / Plays-First-Edition variant
            # if available; otherwise grab the first printing.
            options = candidates_by_name[name]
            chosen = next(
                (c for c in options if c.get("treatment") == "Plays"),
                options[0]
            )
            replacements.append(chosen["bobaId"])
            seen_names.add(name)

        new_plays = kept + replacements
        templates[tid]["playIds"] = new_plays
        total_swaps += dup_slots
        print(f"  {tid}: {len(plays)} → {len(new_plays)} plays "
              f"(swapped {dup_slots}, top fills: {ranked_names[:dup_slots]})")

    out_text = json.dumps(templates, indent=2) + "\n"
    TEMPLATES.write_text(out_text)
    if IOS_TEMPLATES.exists():
        IOS_TEMPLATES.write_text(out_text)
    print(f"\nWrote {TEMPLATES.relative_to(ROOT)}")
    if IOS_TEMPLATES.exists():
        print(f"Wrote {IOS_TEMPLATES.relative_to(ROOT)}")
    print(f"Total slots swapped: {total_swaps}")


if __name__ == "__main__":
    main()
