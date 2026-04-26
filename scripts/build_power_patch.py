#!/usr/bin/env python3
"""Turn the OCR audit output into a power-realign patch.

Reads the JSON produced by `audit_card_powers.swift`, partitions rows
into:
  - high-confidence mismatches → `modify[]` entries in the patch
  - low-confidence mismatches → `needs_review.json` (operator to OCR
    by hand or skip)
  - high-confidence matches → silent (catalog is correct)

Patch shape mirrors the hot-dog handoff so `apply_*` scripts share the
schema:
{
  "modify": [
    {
      "old_bobaId": "ABF-326-Dunker-Alpha Battlefoil-John Starks Debut",
      "changes":   {"power": 140},
      "reason":    "OCR-confirmed printed power 140 (catalog had 160); confidence 1.00"
    },
    ...
  ]
}

Usage:
  python3 scripts/build_power_patch.py \
    --audit /tmp/power-audit-full.json \
    --out-dir handoff-updates-2026-04-26/power-realign \
    [--confidence 0.85]
"""

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--audit", required=True, type=Path)
    ap.add_argument("--out-dir", required=True, type=Path)
    ap.add_argument(
        "--confidence",
        type=float,
        default=0.85,
        help="Mismatches below this confidence go to needs_review.json instead of the patch",
    )
    args = ap.parse_args()

    audit = json.loads(args.audit.read_text())
    rows = audit["results"]
    args.out_dir.mkdir(parents=True, exist_ok=True)

    patch_modify = []
    needs_review = []
    no_power = []
    matches = 0
    delta_hist = Counter()
    prefix_changes = Counter()

    for r in rows:
        ocr = r.get("ocrPower")
        cat = r.get("catalogPower")
        conf = r.get("confidence", 0)
        bid = r["bobaId"]

        if ocr is None:
            no_power.append(
                {"bobaId": bid, "catalogPower": cat, "candidates": r.get("candidates", [])}
            )
            continue

        if ocr == cat:
            matches += 1
            continue

        # Mismatch — high vs low confidence
        delta = (ocr - cat) if (cat is not None) else None
        prefix = bid.split("-", 1)[0] if "-" in bid else "?"
        record = {
            "bobaId": bid,
            "catalogPower": cat,
            "ocrPower": ocr,
            "confidence": round(conf, 3),
            "delta": delta,
            "candidates": r.get("candidates", []),
        }
        if conf >= args.confidence:
            patch_modify.append(
                {
                    "old_bobaId": bid,
                    "changes": {"power": ocr},
                    "reason": (
                        f"OCR-confirmed printed power {ocr} "
                        f"(catalog had {cat}); confidence {conf:.2f}"
                    ),
                }
            )
            if delta is not None:
                delta_hist[delta] += 1
            prefix_changes[prefix] += 1
        else:
            needs_review.append(record)

    # Write the patch.
    patch = {
        "schema_decision": (
            "Power realignment from OCR. Each modify entry sets only the "
            "power field; bobaId is unchanged (not derived from power)."
        ),
        "modify": patch_modify,
        "stats": {
            "total_inspected": len(rows),
            "matches": matches,
            "high_conf_mismatches": len(patch_modify),
            "low_conf_mismatches": len(needs_review),
            "no_power_extracted": len(no_power),
            "confidence_threshold": args.confidence,
        },
    }
    patch_path = args.out_dir / "patch.json"
    patch_text = json.dumps(patch, indent=2, ensure_ascii=False)
    patch_path.write_text(patch_text)
    md5 = hashlib.md5(patch_text.encode()).hexdigest()

    needs_review_path = args.out_dir / "needs_review.json"
    needs_review_path.write_text(
        json.dumps(
            {"low_conf_mismatches": needs_review, "no_power_extracted": no_power},
            indent=2,
            ensure_ascii=False,
        )
    )

    # Build a lightweight markdown report.
    lines = [
        "# Power realignment audit",
        "",
        "Built from OCR over the existing R2 thumbnails. The R2 art is the",
        "ground truth for each card's printed power; the catalog metadata is",
        "what the engine reads. Where they disagree, this patch sets the",
        "catalog's `power` to match the print.",
        "",
        "## Stats",
        "",
        f"- Total Hero records inspected:        **{len(rows):,}**",
        f"- Catalog already correct:             **{matches:,}**",
        f"- Mismatches (high-confidence, patched): **{len(patch_modify):,}**",
        f"- Mismatches (low-confidence, queued for review): **{len(needs_review):,}**",
        f"- OCR returned no power (queued for review): **{len(no_power):,}**",
        f"- Confidence threshold for auto-patch:  `{args.confidence}`",
        "",
        "## Power-delta histogram (patched rows only)",
        "",
        "| Δ (ocr − catalog) | rows |",
        "|---:|---:|",
    ]
    for d in sorted(delta_hist.keys()):
        lines.append(f"| {d:+d} | {delta_hist[d]} |")
    lines += [
        "",
        "## Per-cardNumber-prefix counts (patched rows only)",
        "",
        "| Prefix | rows |",
        "|---|---:|",
    ]
    for p, n in prefix_changes.most_common(30):
        lines.append(f"| {p} | {n} |")
    lines += [
        "",
        "## Files",
        "",
        f"- `patch.json` — apply via `scripts/apply_power_realign.py`",
        f"  - md5: `{md5}`",
        f"- `needs_review.json` — low-confidence rows (OCR was uncertain) and",
        "  rows where OCR couldn't extract a power at all. Operator to spot",
        "  check or skip.",
        "",
        "## Migration footprint",
        "",
        "Power changes do not affect `bobaId` (the formula is",
        "`cardNumber-hero-treatment-variation`). No R2 renames, no Supabase",
        "row migration needed. Just a JSON field update applied to the",
        "master + 4 downstream bundles.",
    ]
    report_path = args.out_dir / "COWORK_POWER_REALIGN.md"
    report_path.write_text("\n".join(lines))

    print(f"Wrote {patch_path}")
    print(f"  md5: {md5}")
    print(f"  modify entries: {len(patch_modify)}")
    print(f"Wrote {needs_review_path} ({len(needs_review)} low-conf, {len(no_power)} no-power)")
    print(f"Wrote {report_path}")


if __name__ == "__main__":
    main()
