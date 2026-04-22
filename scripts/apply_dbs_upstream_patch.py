#!/usr/bin/env python3
"""
apply_dbs_upstream_patch.py — write Cowork's authored DBS values for the
30 Plays that aren't in the official deckbuilder yet (Superfan Series +
World Champions subsets), plus mop up the 3 live-scrape names that
propagate_dbs.py's key-normalization should already have caught.

Input:  /Users/bhwilkoff/…/Bo Jackson Battle Arena Research/handoff-updates-2026-04-22/dbs/dbs_upstream_patch.json
Output: Research-project cards.json updated, bundles regenerated, synced
        into the BOBA-Playbook repo.

Runs after scripts/propagate_dbs.py (the propagator fills everything it
can via same-name inheritance; this script fills the rest).
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

APP_REPO = Path(__file__).resolve().parent.parent
RESEARCH = Path("/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research")
R_DATA   = RESEARCH / "unified-cards" / "data"
R_CARDS  = R_DATA / "cards.json"
APP_DATA = APP_REPO / "assets" / "data"
APP_IOS  = APP_REPO / "BOBAPlaybook"

PATCH = RESEARCH / "handoff-updates-2026-04-22" / "dbs" / "dbs_upstream_patch.json"

def flatten_patch(patch: dict) -> dict[str, tuple[int, str]]:
    """Flatten {section: {name: {dbs, dbsTier, ...}}} → {name: (dbs, dbsTier)}."""
    vals: dict[str, tuple[int, str]] = {}
    for section in ("recovered_from_official_deckbuilder", "authored_from_analogs"):
        for name, entry in (patch.get(section) or {}).items():
            if name.startswith("_"): continue  # skip _note / _meta markers
            vals[name] = (entry["dbs"], entry["dbsTier"])
    return vals

def main():
    patch = json.loads(PATCH.read_text())
    vals = flatten_patch(patch)
    print(f"Patch carries {len(vals)} entries")

    cards = json.loads(R_CARDS.read_text())
    before_nulls = sum(1 for c in cards if c.get("cardType") == "Play" and c.get("dbs") is None)
    print(f"Plays missing DBS before patch: {before_nulls}")

    updated = 0
    per_name: dict[str, int] = {}
    for c in cards:
        if c.get("cardType") != "Play": continue
        if c.get("dbs") is not None: continue
        name = c.get("name")
        if name in vals:
            c["dbs"], c["dbsTier"] = vals[name]
            updated += 1
            per_name[name] = per_name.get(name, 0) + 1

    after_nulls = sum(1 for c in cards if c.get("cardType") == "Play" and c.get("dbs") is None)
    print(f"Plays missing DBS after patch:  {after_nulls}  ({updated} printings filled)")
    if per_name:
        print("Names filled (top 10):")
        for n, ct in sorted(per_name.items())[:10]:
            dbs, tier = vals[n]
            print(f"  {n:<32} → dbs={dbs} tier={tier}  ({ct} printings)")

    # Any patch entries not applied? (Already had a value, or catalog-name not found)
    applied_keys = {n for n, _ in per_name.items() if per_name.get(n, 0) > 0}
    unapplied = [n for n in vals if n not in applied_keys]
    if unapplied:
        print(f"\n{len(unapplied)} patch entries not applied (may already be tagged "
              f"via propagator or name mismatch):")
        for n in unapplied:
            print(f"  {n}")

    R_CARDS.write_text(json.dumps(cards, indent=2, ensure_ascii=False))

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

    print("\nSyncing bundles to BOBA-Playbook repo …")
    for name in ("cards.json", "cards-slim.json", "categories.json",
                 "search-index.json", "missing-cards.json"):
        src, dst = R_DATA / name, APP_DATA / name
        if src.exists():
            shutil.copy2(src, dst)
            print(f"  {name}: {dst.stat().st_size:,} bytes")

    cards_app = json.loads((APP_DATA / "cards.json").read_text())
    # Sealed products stay in the iOS bundle (reversed 2026-04-22).
    display = cards_app
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
