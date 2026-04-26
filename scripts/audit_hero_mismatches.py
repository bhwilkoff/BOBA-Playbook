#!/usr/bin/env python3
"""Scan the existing OCR audit data for hero/image mismatches across
EVERY Hero record (not just the power-mismatch subset).

The power-realign patch's hero-match guard caught 24 wrong-image cases
— but only among the 875 rows where catalog power and OCR power
disagreed. Wrong-image collisions where the wrong art's printed power
happens to match the catalog's stated power slip through that filter
silently.

This script consumes the same audit JSON the power patch consumes,
ignores the power comparison entirely, and just asks: for each row,
did the OCR capture a hero name, and does it match the catalog hero?

Output: `handoff-updates-2026-04-26/hero-mismatches/wrong_images.json`
+ a markdown report. NO patch is produced — fixing this requires
re-sourcing the art on R2, which is outside what an OCR-driven
catalog patch can do.

Usage:
  python3 scripts/audit_hero_mismatches.py \
    --audit /tmp/power-audit-full.json \
    --out-dir handoff-updates-2026-04-26/hero-mismatches
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
from build_power_patch import hero_in_candidates  # reuse the matcher


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--audit", required=True, type=Path)
    ap.add_argument("--out-dir", required=True, type=Path)
    ap.add_argument(
        "--catalog",
        type=Path,
        default=Path(
            "/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research"
            "/unified-cards/data/cards.json"
        ),
    )
    args = ap.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    catalog = json.loads(args.catalog.read_text())
    catalog_by_bid = {c["bobaId"]: c for c in catalog if c.get("bobaId")}

    # Build a set of all unique hero names in the catalog so we can
    # check whether an OCR-captured token corresponds to a DIFFERENT
    # known hero. The strict bucket only flags rows where the OCR
    # captured a hero name from this set that doesn't match the
    # catalog row's hero — those are unambiguous wrong-image bugs.
    # Loose-bucket rows (OCR noise / fragments) are too unreliable
    # to act on at scale.
    all_heroes = set()
    for c in catalog:
        h = c.get("hero")
        if h and c.get("cardType") == "Hero":
            all_heroes.add(h)

    audit = json.loads(args.audit.read_text())
    rows = audit["results"]

    confirmed = 0
    confirmed_wrong = []   # OCR captured a different KNOWN hero
    possible_wrong = []    # OCR didn't match catalog AND no known hero either
    inconclusive = 0

    for r in rows:
        bid = r["bobaId"]
        catalog_row = catalog_by_bid.get(bid)
        if catalog_row is None:
            continue
        hero = catalog_row.get("hero") or ""
        verdict = hero_in_candidates(hero, r.get("candidates", []))
        if verdict is True:
            confirmed += 1
            continue
        if verdict is None:
            inconclusive += 1
            continue

        # Verdict is False — OCR captured alpha tokens but none
        # matched the catalog hero. Try to identify whether one of
        # the captured tokens IS a different known hero from the
        # catalog. If so, this is a confirmed wrong-image bug. If
        # not, it's likely OCR noise on stylized art and we can't
        # reliably distinguish from a real bug.
        candidates = r.get("candidates", [])
        alpha_cands = [c for c in candidates
                       if any(ch.isalpha() for ch in c) and len(c) >= 3]

        identified_other = None
        for other_hero in all_heroes:
            if other_hero == hero:
                continue
            v = hero_in_candidates(other_hero, candidates)
            if v is True:
                identified_other = other_hero
                break

        record = {
            "bobaId": bid,
            "catalogHero": hero,
            "catalogCardNumber": catalog_row.get("cardNumber"),
            "catalogTreatment": catalog_row.get("treatment"),
            "catalogElement": catalog_row.get("element"),
            "catalogPower": catalog_row.get("power"),
            "ocrCandidates": alpha_cands[:5],
            "imageFile": catalog_row.get("imageFile"),
            "identifiedAs": identified_other,
        }
        if identified_other is not None:
            confirmed_wrong.append(record)
        else:
            possible_wrong.append(record)

    mismatch = confirmed_wrong  # alias used by the rest of the function

    total = len(rows)
    print(f"Hero/image mismatch scan over {total:,} rows:")
    print(f"  Hero confirmed (image matches catalog):       {confirmed:,} ({confirmed/total:.1%})")
    print(f"  Image is a DIFFERENT KNOWN hero (high conf):  {len(confirmed_wrong):,} ({len(confirmed_wrong)/total:.1%})")
    print(f"  Mismatched but OCR too noisy to identify:     {len(possible_wrong):,} ({len(possible_wrong)/total:.1%})")
    print(f"  Inconclusive (no hero text captured):         {inconclusive:,} ({inconclusive/total:.1%})")

    # Group mismatches by treatment / cardNumber prefix for the report.
    by_treatment: Counter = Counter()
    by_prefix: Counter = Counter()
    for m in mismatch:
        by_treatment[m.get("catalogTreatment") or "(unknown)"] += 1
        cn = m.get("catalogCardNumber") or ""
        prefix = cn.split("-", 1)[0] if "-" in cn else cn
        by_prefix[prefix] += 1

    out = {
        "summary": {
            "totalScanned": total,
            "heroConfirmed": confirmed,
            "confirmedWrongImage": len(confirmed_wrong),
            "possibleWrongImageOrOcrNoise": len(possible_wrong),
            "inconclusive": inconclusive,
        },
        "byTreatment": dict(by_treatment.most_common()),
        "byPrefix": dict(by_prefix.most_common()),
        "confirmedWrong": confirmed_wrong,
        "possibleWrongOrNoise": possible_wrong,
    }
    out_json = args.out_dir / "wrong_images.json"
    out_json.write_text(json.dumps(out, indent=2, ensure_ascii=False))
    print(f"\nWrote {out_json}")

    # Markdown report.
    lines = [
        "# Hero/image mismatch scan",
        "",
        "Catalog-wide scan for cases where the R2 image at a bobaId's slug",
        "shows a DIFFERENT hero than the catalog row's `hero` field.",
        "Caused by past R2 sync bugs / image-overwrite collisions",
        "(DECISIONS.md #026). Patching `power` on these rows is unsafe —",
        "what's needed is a re-source of the correct art onto the catalog's",
        "slug.",
        "",
        "## Summary",
        "",
        f"- Hero records scanned:                              **{total:,}**",
        f"- Confirmed image matches catalog hero:              **{confirmed:,}** ({confirmed/total:.1%})",
        f"- **Confirmed WRONG image** (OCR found a different known hero): **{len(confirmed_wrong):,}** ({len(confirmed_wrong)/total:.1%})",
        f"- Mismatched but OCR too noisy to identify:          **{len(possible_wrong):,}** ({len(possible_wrong)/total:.1%})",
        f"- Inconclusive (OCR captured no hero text at all):   **{inconclusive:,}** ({inconclusive/total:.1%})",
        "",
        "The 'confirmed wrong' bucket is the actionable one — for each row,",
        "the OCR captured a hero name that matches a DIFFERENT real hero in",
        "the catalog. There's no plausible OCR-noise explanation; the file",
        "at the catalog row's slug is genuinely the art for a different",
        "hero. The 'too noisy to identify' bucket may include real wrong-",
        "image cases the OCR couldn't disambiguate from glyph noise on",
        "stylized art (Mixtape, Miami Ice, Kanjifoil etc.) — manual review",
        "is the only reliable disposition for those.",
        "",
        "## By treatment",
        "",
        "| Treatment | wrong-image rows |",
        "|---|---:|",
    ]
    for t, n in by_treatment.most_common():
        lines.append(f"| {t} | {n} |")
    lines += [
        "",
        "## By cardNumber prefix",
        "",
        "| Prefix | wrong-image rows |",
        "|---|---:|",
    ]
    for p, n in by_prefix.most_common():
        lines.append(f"| {p} | {n} |")
    lines += [
        "",
        "## What to do with this",
        "",
        "Each row in `wrong_images.json` lists the catalog hero, OCR-captured",
        "hero candidates, and the imageFile slug. The fix is to:",
        "",
        "1. Decide whether the catalog's hero+treatment combo is correct",
        "   (look up the canonical checklist) and the IMAGE was wrongly",
        "   uploaded under that slug",
        "2. OR the catalog's hero is wrong and the IMAGE matches a real",
        "   different hero",
        "",
        "In case (1) — re-source the correct art onto R2 under the slug.",
        "In case (2) — fix the catalog row's hero (and bobaId).",
        "",
        "Either fix is OUTSIDE the scope of this script — it just surfaces",
        "the rows that need attention.",
    ]
    out_md = args.out_dir / "WRONG_IMAGES_REPORT.md"
    out_md.write_text("\n".join(lines))
    print(f"Wrote {out_md}")


if __name__ == "__main__":
    main()
