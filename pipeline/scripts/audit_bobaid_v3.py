#!/usr/bin/env python3
"""
audit_bobaid_v3.py — assert that the v3 bobaId migration is fully
applied across every catalog file and every derived data file that
references cards by bobaId.

Exits 0 when every check passes. Exits 1 with a categorized report
on any divergence. Safe to run in CI.

USAGE
-----
    python3 pipeline/scripts/audit_bobaid_v3.py

WHAT IT CHECKS
--------------
For each of the 5 catalog bundles (master + 4 derived):
  1. Every card's stored `bobaId` field equals the canonical v3
     formula output (5-field). Identifies any v2 stragglers.
  2. Every card has a non-empty bobaId.
  3. Every bobaId is unique within the bundle (no collisions).

For each derived data file that REFERENCES bobaIds:
  - categories.json (web + Android)
  - search-index.json (web)
  - template-decks.json (web)
  - TemplateDeck.json (iOS + Android)
  Every bobaId-shaped value resolves to a real catalog row. Known-
  orphan refs (e.g. Flavor Flav Sidekicks rows that never existed)
  are tolerated via the KNOWN_ORPHANS set below.

Doesn't check Supabase (would need network + service key); the
v3 migration script ran against Supabase end-of-batch on
2026-05-25 and any subsequent drift would only happen if someone
manually inserted v2 rows. Add a Supabase check if that becomes a
risk.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "scripts"))
from boba_id import boba_id  # canonical v3 formula

MASTER = REPO / "assets/data/cards.json"
BUNDLES = [
    REPO / "assets/data/cards.json",
    REPO / "assets/data/cards-head.json",
    REPO / "BOBAPlaybook/display-cards.json",
    REPO / "BOBAPlaybook/cards-head.json",
    REPO / "android/app/src/main/assets/data/cards.json",
]
DERIVED = [
    REPO / "assets/data/categories.json",
    REPO / "assets/data/search-index.json",
    REPO / "assets/data/template-decks.json",
    REPO / "BOBAPlaybook/TemplateDeck.json",
    REPO / "android/app/src/main/assets/TemplateDeck.json",
    REPO / "android/app/src/main/assets/data/categories.json",
]

# Refs we know aren't in the catalog and aren't worth resolving —
# documented missing rows from prior audits.
KNOWN_ORPHANS = {
    "FFA-3-Flavor Flav-Sidekicks-Flavor Flav Debut",
    "FFA-6-Flavor Flav-Sidekicks-Flavor Flav Debut",
    "GBF-41-Skeee-Green Battlefoil-First Edition",
    # The Apple Maps app contains text strings that are accidentally
    # bobaId-shaped — add others here as they're identified.
}

# A "v3 shape" bobaId has 4+ dashes overall. We also accept v3 with
# trailing empty fields (e.g. Showtime---ICE has 3 dashes between
# hero and element). Use a loose pattern then double-check via formula.
BOBAID_LIKE = re.compile(r"^[A-Za-z0-9_./\-]+-[^-]*-[^-]*-[^-]*$")


def find_bobaid_refs(obj):
    """Yield every bobaId-shaped string from a nested structure."""
    if isinstance(obj, str):
        # Heuristic: cardNumber-prefixed + at least 3 internal dashes.
        if obj.count("-") >= 3 and obj[0:1].isalnum() and len(obj) < 300:
            yield obj
    elif isinstance(obj, list):
        for x in obj:
            yield from find_bobaid_refs(x)
    elif isinstance(obj, dict):
        for k, v in obj.items():
            # Also check keys — categories.json keys are filter names,
            # not bobaIds, but search-index.json's byHero/byElement
            # keys are facet labels too. Skip key checking entirely.
            yield from find_bobaid_refs(v)


def check_bundle(path: Path):
    issues = []
    cards = json.loads(path.read_text())
    if isinstance(cards, dict) and "cards" in cards:
        cards = cards["cards"]
    n = len(cards)
    seen_bids = set()
    v2_count = 0
    missing_count = 0
    mismatch_count = 0
    dupe_count = 0
    samples = []
    for c in cards:
        stored = c.get("bobaId")
        if not stored:
            missing_count += 1
            continue
        # Recompute expected v3.
        expected = boba_id(c)
        if stored != expected:
            mismatch_count += 1
            if len(samples) < 5:
                samples.append((stored, expected))
        # v2 detection: 3 dashes only (no element).
        if stored.count("-") == 3:
            v2_count += 1
        if stored in seen_bids:
            dupe_count += 1
        seen_bids.add(stored)
    if missing_count or mismatch_count or dupe_count or v2_count:
        issues.append(f"  cards={n}  missing_bobaId={missing_count}  "
                      f"v2_shape={v2_count}  stored≠computed={mismatch_count}  "
                      f"duplicates={dupe_count}")
        if samples:
            issues.append("  Sample stored≠computed:")
            for stored, expected in samples:
                issues.append(f"    stored:   {stored}")
                issues.append(f"    computed: {expected}")
    return n, issues


def check_derived(path: Path, catalog: set[str]):
    issues = []
    data = json.loads(path.read_text())
    refs = list(find_bobaid_refs(data))
    unique_refs = set(refs)
    orphans = [r for r in unique_refs if r not in catalog and r not in KNOWN_ORPHANS]
    v2_shaped = [r for r in unique_refs if r.count("-") == 3]
    if orphans or v2_shaped:
        issues.append(f"  refs={len(refs)}  unique={len(unique_refs)}  "
                      f"v2_shape={len(v2_shaped)}  unresolvable={len(orphans)}")
        if orphans:
            issues.append("  Unresolvable refs (sample):")
            for o in sorted(orphans)[:8]:
                issues.append(f"    {o}")
            if len(orphans) > 8:
                issues.append(f"    … and {len(orphans)-8} more")
    return len(refs), issues


def main() -> int:
    print("=== bobaId v3 audit ===\n")
    total_issues = 0

    print(f"[1/2] Catalog bundles ({len(BUNDLES)})")
    catalog: set[str] = set()
    for path in BUNDLES:
        if not path.exists():
            print(f"  ✗ MISSING: {path}")
            total_issues += 1
            continue
        n, issues = check_bundle(path)
        rel = path.relative_to(REPO)
        if issues:
            print(f"  ✗ {rel} ({n} cards)")
            for line in issues:
                print(line)
            total_issues += 1
        else:
            print(f"  ✓ {rel} ({n} cards)")
        if path == MASTER:
            catalog = {c.get("bobaId") for c in json.loads(path.read_text()) if c.get("bobaId")}

    print(f"\n[2/2] Derived data files referencing bobaIds ({len(DERIVED)})")
    for path in DERIVED:
        if not path.exists():
            print(f"  ✗ MISSING: {path}")
            total_issues += 1
            continue
        n, issues = check_derived(path, catalog)
        rel = path.relative_to(REPO)
        if issues:
            print(f"  ✗ {rel} ({n} refs)")
            for line in issues:
                print(line)
            total_issues += 1
        else:
            print(f"  ✓ {rel} ({n} refs)")

    print(f"\n=== {'PASS' if not total_issues else 'FAIL'} — {total_issues} file(s) with issues ===")
    return 0 if not total_issues else 1


if __name__ == "__main__":
    sys.exit(main())
