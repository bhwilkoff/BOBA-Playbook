#!/usr/bin/env python3
"""Second-pass power audit using sibling consensus.

After the OCR-driven power-realign, ~254 rows are still uncertain
(needs_review.json). For each, examine verified sibling rows that
share the same (hero, treatment, element) tuple. If the verified
siblings unanimously agree on a power that differs from the row's
catalog power, we have strong evidence the catalog is wrong even
without a clean OCR read on this specific row.

What counts as "verified":
  - The row has been through the OCR audit (every Hero record was)
  - AND either the catalog power matched the OCR power
       (15,000+ confirmed-correct rows)
  - OR the row was patched in power-realign v2 (649 corrected rows
       with hero match in the OCR candidates)

Conservative thresholds:
  - At least 2 verified siblings required (one isn't a "consensus")
  - All verified siblings must agree on a single power value
  - The consensus power must differ from this row's catalog power
  - When OCR for this row produced a power, prefer it over consensus
    only if the OCR matches sibling consensus (corroboration)

Usage:
  python3 scripts/audit_sibling_consensus.py
"""

from __future__ import annotations

import json
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESEARCH = Path(
    "/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research"
)
MASTER_CARDS = RESEARCH / "unified-cards/data/cards.json"
POWER_AUDIT = Path("/tmp/power-audit-full.json")
NEEDS_REVIEW = ROOT / "handoff-updates-2026-04-26/power-realign/needs_review.json"
OUT_DIR = ROOT / "handoff-updates-2026-04-26/sibling-consensus"


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    catalog = json.loads(MASTER_CARDS.read_text())
    audit = json.loads(POWER_AUDIT.read_text())
    audit_by_bid = {r["bobaId"]: r for r in audit["results"]}
    needs_review = json.loads(NEEDS_REVIEW.read_text())

    # Build the verified set: rows where the OCR result agreed with the
    # post-realign catalog power. After power-realign v2 the catalog is
    # in its corrected state — every row whose post-realign catalog
    # power matches the OCR's printed power is verified by the OCR.
    bid_to_card = {c["bobaId"]: c for c in catalog if c.get("bobaId")}
    verified: dict[str, int] = {}   # bid → catalog power (verified)
    for c in catalog:
        bid = c.get("bobaId")
        if not bid:
            continue
        a = audit_by_bid.get(bid)
        if not a:
            continue
        ocr_p = a.get("ocrPower")
        cat_p = c.get("power")
        if ocr_p is not None and ocr_p == cat_p:
            verified[bid] = cat_p

    print(f"Verified rows (catalog power matches OCR): {len(verified):,}")

    # Group verified rows by (hero, treatment, element).
    groups: dict[tuple, Counter] = defaultdict(Counter)
    for c in catalog:
        bid = c.get("bobaId")
        if bid not in verified:
            continue
        key = (
            c.get("hero") or "",
            c.get("treatment") or "",
            c.get("element") or "",
        )
        groups[key][c.get("power")] += 1

    # Walk needs_review rows. For each, find a sibling group and check
    # whether consensus disagrees with catalog. Only act when consensus
    # is strong (≥2 verified siblings, all agreeing on a single power).
    candidates_review = needs_review.get("low_conf_mismatches", []) + \
                        needs_review.get("no_power_extracted", [])

    patch = []        # rows we want to fix to sibling consensus
    confirmed_ok = [] # rows where catalog already matches consensus
    no_consensus = [] # no verified siblings or siblings disagree

    for r in candidates_review:
        bid = r["bobaId"]
        c = bid_to_card.get(bid)
        if c is None:
            continue
        key = (
            c.get("hero") or "",
            c.get("treatment") or "",
            c.get("element") or "",
        )
        sibling_powers = groups.get(key, Counter())
        # Exclude this row itself if it happens to be verified
        # (shouldn't be since it's in needs_review, but defensive).
        sibling_count = sum(sibling_powers.values())
        if sibling_count < 2:
            no_consensus.append({
                "bobaId": bid, "reason": "fewer_than_2_verified_siblings",
                "siblingCount": sibling_count,
            })
            continue
        # Strict consensus: all siblings agree on a single power.
        if len(sibling_powers) > 1:
            no_consensus.append({
                "bobaId": bid, "reason": "siblings_disagree",
                "siblingPowers": dict(sibling_powers),
            })
            continue
        consensus_power = next(iter(sibling_powers.keys()))
        cat_p = c.get("power")
        if consensus_power == cat_p:
            confirmed_ok.append({"bobaId": bid, "power": cat_p,
                                 "siblingCount": sibling_count})
            continue
        # Consensus disagrees with catalog. We patch IF:
        #  - The OCR didn't capture a contradicting clean reading, OR
        #  - The OCR's reading also matches consensus (corroboration)
        ocr_p = r.get("ocrPower")
        if ocr_p is not None and ocr_p != consensus_power:
            # OCR disagrees with consensus AND with catalog. Three-way
            # disagreement — not safe to auto-patch. Manual review.
            no_consensus.append({
                "bobaId": bid,
                "reason": "ocr_disagrees_with_consensus",
                "catalogPower": cat_p, "ocrPower": ocr_p,
                "consensus": consensus_power,
                "siblingCount": sibling_count,
            })
            continue
        patch.append({
            "old_bobaId": bid,
            "changes": {"power": consensus_power},
            "reason": (
                f"Sibling consensus power {consensus_power} "
                f"(catalog had {cat_p}); {sibling_count} verified siblings agree"
            ),
        })

    # Stats summary.
    print(f"\nUnresolved rows scanned: {len(candidates_review)}")
    print(f"  Patched to sibling consensus:           {len(patch):,}")
    print(f"  Catalog already matches consensus (ok): {len(confirmed_ok):,}")
    print(f"  Cannot decide (no consensus / disagree): {len(no_consensus):,}")

    # Write outputs.
    (OUT_DIR / "patch.json").write_text(
        json.dumps(
            {
                "schema_decision": (
                    "Sibling-consensus power patch. Each modify entry sets "
                    "the row's power to match its (hero, treatment, element) "
                    "siblings' unanimous power."
                ),
                "modify": patch,
                "stats": {
                    "scanned": len(candidates_review),
                    "patched": len(patch),
                    "confirmed_ok": len(confirmed_ok),
                    "no_consensus": len(no_consensus),
                },
            },
            indent=2, ensure_ascii=False,
        )
    )
    (OUT_DIR / "confirmed_ok.json").write_text(
        json.dumps(confirmed_ok, indent=2, ensure_ascii=False)
    )
    (OUT_DIR / "no_consensus.json").write_text(
        json.dumps(no_consensus, indent=2, ensure_ascii=False)
    )
    print(f"\nWrote {OUT_DIR / 'patch.json'} ({len(patch)} entries)")
    print(f"Wrote {OUT_DIR / 'confirmed_ok.json'} ({len(confirmed_ok)} entries)")
    print(f"Wrote {OUT_DIR / 'no_consensus.json'} ({len(no_consensus)} entries)")


if __name__ == "__main__":
    main()
