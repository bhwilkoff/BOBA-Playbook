#!/usr/bin/env python3
"""
propagate_dbs.py — copy canonical (dbs, dbsTier) across all printings of a Play.

DBS is a per-card-name mechanical property, but the official-deckbuilder
enrichment in reconcile_all.py::step13 only matches (name + set + variation
+ treatment) exactly, leaving reprints/starter variants without DBS data
even though the canonical value is known on another printing.

This script closes the gap: for every Play name that has DBS on at least
one printing, propagate that (dbs, dbsTier) to every other printing of the
same name. Refuses to propagate if two printings of the same name report
DIFFERENT values (would be a real data bug, not a propagation gap). None
were present at time of authoring.

Keys are normalized (lowercased, punctuation stripped) before matching so
catalog quirks like 'Pinch HItter' vs 'Pinch Hitter' or 'Double or Nothin'
vs 'Double or Nothin'' collapse to the same bucket. The canonical display
form is taken from the first tagged printing seen.

Writes the research-project cards.json, runs reconcile_all.py step 5/6/8/9,
and syncs the regenerated bundles into the BOBA-Playbook repo.
"""

import json
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

APP_REPO = Path(__file__).resolve().parent.parent
RESEARCH = Path("/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research")
R_DATA   = RESEARCH / "unified-cards" / "data"
R_CARDS  = R_DATA / "cards.json"
APP_DATA = APP_REPO / "assets" / "data"
APP_IOS  = APP_REPO / "BOBAPlaybook"

def _norm_key(name: str) -> str:
    """Normalized key for matching play names across catalog quirks.

    Collapses case and strips non-alphanumerics so `Pinch HItter` and
    `Pinch Hitter` hash the same, and `Double or Nothin'` matches
    `Double or Nothin`.
    """
    return re.sub(r'[^a-z0-9]', '', (name or '').lower())


def main():
    cards = json.loads(R_CARDS.read_text())
    plays = [c for c in cards if c.get("cardType") == "Play"]

    # Canonical (dbs, dbsTier) per normalized play-name key, plus conflict guard.
    # Keyed by the normalized form so spelling quirks don't miss the lookup.
    canonical_values: dict[str, set[tuple]] = defaultdict(set)
    for p in plays:
        if p.get("dbs") is not None:
            canonical_values[_norm_key(p["name"])].add((p["dbs"], p.get("dbsTier")))

    conflicts = {k: v for k, v in canonical_values.items() if len(v) > 1}
    if conflicts:
        print("ABORT — internal DBS conflicts across printings:")
        for k, v in conflicts.items():
            print(f"  {k}: {v}")
        sys.exit(2)

    canonical = {k: next(iter(v)) for k, v in canonical_values.items()}
    print(f"Play names (normalized keys) with canonical DBS: {len(canonical)}")

    # Propagate via normalized-key lookup
    before = sum(1 for p in plays if p.get("dbs") is None)
    filled = 0
    still_missing_names: set[str] = set()
    for c in cards:
        if c.get("cardType") != "Play": continue
        if c.get("dbs") is not None: continue
        canon = canonical.get(_norm_key(c["name"]))
        if canon:
            c["dbs"], c["dbsTier"] = canon
            filled += 1
        else:
            still_missing_names.add(c["name"])

    after = sum(1 for c in cards if c.get("cardType") == "Play" and c.get("dbs") is None)
    print(f"Plays missing DBS: {before} → {after}  ({filled} printings propagated)")
    print(f"Play names still fully untagged: {len(still_missing_names)}")

    R_CARDS.write_text(json.dumps(cards, indent=2, ensure_ascii=False))

    # Regen downstream bundles
    print("\nRegenerating bundles via reconcile_all.py …")
    for step in (5, 6, 8, 9):
        res = subprocess.run(
            [sys.executable, "reconcile_all.py", "--step", str(step)],
            cwd=RESEARCH, capture_output=True, text=True,
        )
        if res.returncode != 0:
            print(res.stdout); print(res.stderr, file=sys.stderr)
            raise RuntimeError(f"reconcile_all.py --step {step} failed")
        print(f"  --step {step} ✓")

    # Sync bundles
    print("\nSyncing bundles to BOBA-Playbook repo …")
    for name in ("cards.json", "cards-slim.json", "categories.json",
                 "search-index.json", "missing-cards.json"):
        src, dst = R_DATA / name, APP_DATA / name
        if src.exists():
            shutil.copy2(src, dst)
            print(f"  {name}: {dst.stat().st_size:,} bytes")

    cards_app = json.loads((APP_DATA / "cards.json").read_text())
    display = [c for c in cards_app if c.get("cardType") != "Sealed Product"]
    head = display[:500]
    (APP_IOS / "display-cards.json").write_text(
        json.dumps(display, separators=(", ", ": "), ensure_ascii=False))
    (APP_IOS / "cards-head.json").write_text(
        json.dumps(head, separators=(", ", ": "), ensure_ascii=False))
    print(f"  display-cards.json: {len(display):,} cards")
    print(f"  cards-head.json: {len(head):,} cards")

    print("\n✓ Done.")

if __name__ == "__main__":
    main()
