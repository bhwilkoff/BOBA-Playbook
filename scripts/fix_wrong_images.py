#!/usr/bin/env python3
"""Fix wrong-image catalog rows by clearing the imageFile.

For each row in the hero-mismatch audit's confirmedWrong list, the R2
file at the row's `imageFile` slug shows a DIFFERENT real hero than
the catalog row's `hero` field — i.e., the file uploaded to that slug
is wrong art for that catalog identity.

Earlier iteration of this script tried to RENAME catalog rows to match
the OCR'd hero (e.g. catalog "Jeesaw at BLBF-95" → "D-Harp at BLBF-95"
when the printed art is D-Harp). That introduced a class of false
positives where Vision OCR's Cyrillic-Latin glyph confusion produced
near-Levenshtein matches against unrelated heroes ("ATTAH" Cyrillic
read of "Attak" matched "Ante-de-something A" via a permissive edit-
distance pass). The catalog row was originally correct; the rename
would have corrupted it.

Conservative path: just clear the wrong art, queue for re-sourcing.

For each confirmedWrong row:
  - Set `imageFile = null`
  - Set `imageAvailable = false`
  - Set `imageSource = null`
  - Append the row to missing-cards.json with an `ebaySearchQuery`
    so the existing eBay/BV sourcer pipeline picks it up

The catalog row STAYS — we don't shrink the database. No bobaId
changes — no Supabase migration. The on-disk .webp file is left in
place too (orphaned but no-op; can be cleaned up later).

App users will see a placeholder where the wrong art used to be,
which is strictly better than seeing the wrong hero's art. Once
correct art is sourced (Cowork session or eBay sourcer hits), the
imageFile field gets repopulated and the placeholder disappears.

Outputs:
  - Updated master cards.json + 4 downstream bundles
  - handoff-updates-2026-04-26/wrong-image-fix/cleared_rows.json:
    list of all bobaIds that had imageFile cleared
  - Updated unified-cards/data/missing-cards.json (155 new entries)

Usage:
  python3 scripts/fix_wrong_images.py [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESEARCH = Path(
    "/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research"
)
MASTER_CARDS = RESEARCH / "unified-cards/data/cards.json"
MASTER_MISSING = RESEARCH / "unified-cards/data/missing-cards.json"
WEB_CARDS = ROOT / "assets/data/cards.json"
WEB_CATEGORIES = ROOT / "assets/data/categories.json"
WEB_INDEX = ROOT / "assets/data/search-index.json"
IOS_DISPLAY = ROOT / "BOBAPlaybook/display-cards.json"
IOS_HEAD = ROOT / "BOBAPlaybook/cards-head.json"

AUDIT_DIR = ROOT / "handoff-updates-2026-04-26/hero-mismatches"
OUT_DIR = ROOT / "handoff-updates-2026-04-26/wrong-image-fix"

sys.path.insert(0, str(ROOT / "scripts"))
from apply_hot_dog_handoff import build_categories, build_search_index


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true",
                    help="Print what would change without writing any files.")
    args = ap.parse_args()
    if args.dry_run:
        print("=== DRY RUN — no files will be modified ===\n")
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    catalog = json.loads(MASTER_CARDS.read_text())
    audit = json.loads((AUDIT_DIR / "wrong_images.json").read_text())
    by_bid = {c["bobaId"]: i for i, c in enumerate(catalog) if c.get("bobaId")}

    confirmed_wrong = audit["confirmedWrong"]
    print(f"Loaded {len(confirmed_wrong)} confirmed wrong-image rows")

    cleared = []
    missing_appends = []
    skipped = 0
    by_treatment: Counter = Counter()

    for m in confirmed_wrong:
        bid = m["bobaId"]
        idx = by_bid.get(bid)
        if idx is None:
            skipped += 1
            continue
        c = catalog[idx]

        cleared.append({
            "bobaId": bid,
            "catalogHero": c.get("hero"),
            "catalogPower": c.get("power"),
            "treatment": c.get("treatment"),
            "wasImageFile": c.get("imageFile"),
        })
        by_treatment[c.get("treatment") or "?"] += 1

        if not args.dry_run:
            c["imageFile"] = None
            c["imageAvailable"] = False
            c["imageSource"] = None

        missing_appends.append({
            "cardNumber": c.get("cardNumber"),
            "bobaId": c.get("bobaId"),
            "name": c.get("name"),
            "hero": c.get("hero"),
            "cardType": c.get("cardType"),
            "set": c.get("set"),
            "subSet": c.get("subSet"),
            "variation": c.get("variation"),
            "treatment": c.get("treatment"),
            "element": c.get("element"),
            "power": c.get("power"),
            "ebaySearchQuery": (
                f"Bo Jackson Battle Arena {c.get('hero','')} "
                f"{(c.get('treatment') or '')} {c.get('cardNumber','')}".strip()
            ),
        })

    print(f"  Cleared rows:   {len(cleared)}")
    print(f"  Skipped (not found): {skipped}")

    if args.dry_run:
        print("\n[DRY RUN] Would clear imageFile on these treatments:")
        for t, n in by_treatment.most_common():
            print(f"  {t}: {n}")
        return

    # Verify uniqueness — none of these operations change bobaId, so
    # this is just a paranoia check.
    ids_after = [c.get("bobaId") for c in catalog if c.get("bobaId")]
    if len(ids_after) != len(set(ids_after)):
        from collections import Counter as C
        dupes = [k for k, n in C(ids_after).items() if n > 1]
        raise SystemExit(f"COLLISION: {dupes[:5]}")

    # Write the catalog bundles.
    print("\nWriting bundles…")
    master_text = json.dumps(catalog, indent=2, ensure_ascii=False)
    MASTER_CARDS.write_text(master_text)
    WEB_CARDS.write_text(master_text)
    IOS_DISPLAY.write_text(json.dumps(catalog, ensure_ascii=False, separators=(",", ":")))
    IOS_HEAD.write_text(json.dumps(catalog[:500], ensure_ascii=False))
    cats = build_categories(catalog)
    WEB_CATEGORIES.write_text(json.dumps(cats, indent=2, ensure_ascii=False))
    idx_data = build_search_index(catalog)
    WEB_INDEX.write_text(json.dumps(idx_data, indent=2, ensure_ascii=False))
    print(f"  wrote {MASTER_CARDS}")
    print(f"  wrote {WEB_CARDS}")
    print(f"  wrote {IOS_DISPLAY}")
    print(f"  wrote {IOS_HEAD}")
    print(f"  wrote {WEB_CATEGORIES}")
    print(f"  wrote {WEB_INDEX}")

    # cleared_rows.json — full list of what we cleared.
    (OUT_DIR / "cleared_rows.json").write_text(
        json.dumps(
            {"cleared": cleared, "appended_to_missing": missing_appends},
            indent=2, ensure_ascii=False,
        )
    )
    print(f"  wrote {OUT_DIR / 'cleared_rows.json'} ({len(cleared)} rows)")

    # Append to missing-cards.json so the eBay/BV sourcer can repopulate
    # the imageFile when correct art surfaces.
    if MASTER_MISSING.exists():
        missing = json.loads(MASTER_MISSING.read_text())
        existing_bids = {c.get("bobaId") for c in missing.get("cards", [])}
        added = 0
        for new in missing_appends:
            if new.get("bobaId") in existing_bids:
                continue
            missing.setdefault("cards", []).append(new)
            added += 1
        missing.setdefault("summary", {})
        missing["summary"]["missingImages"] = len(missing["cards"])
        MASTER_MISSING.write_text(json.dumps(missing, indent=2, ensure_ascii=False))
        print(f"  appended {added} entries to {MASTER_MISSING}")

    print("\nBy treatment:")
    for t, n in by_treatment.most_common():
        print(f"  {t}: {n}")
    print("\nDone.")


if __name__ == "__main__":
    main()
