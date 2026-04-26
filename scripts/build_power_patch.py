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


def _letters_only(s):
    """Strip everything except letters, uppercased. Normalizes
    "Mic'd Up" → "MICDUP", "Big-Z" → "BIGZ", "Crews-Missle" →
    "CREWSMISSLE" so OCR's tendency to drop punctuation doesn't
    invalidate a match."""
    return "".join(ch for ch in s.upper() if ch.isalpha())


def _edit_distance(a, b, cap=3):
    """Bounded Levenshtein. Returns `cap+1` when distance exceeds
    `cap` so callers can short-circuit. Cap=3 catches single-char
    OCR substitutions (CLUTCH/ELUTCH), missed letters, and one
    inserted glyph at once."""
    if a == b:
        return 0
    if abs(len(a) - len(b)) > cap:
        return cap + 1
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        curr = [i] + [0] * len(b)
        rowmin = curr[0]
        for j, cb in enumerate(b, 1):
            cost = 0 if ca == cb else 1
            curr[j] = min(prev[j] + 1, curr[j-1] + 1, prev[j-1] + cost)
            if curr[j] < rowmin:
                rowmin = curr[j]
        if rowmin > cap:
            return cap + 1
        prev = curr
    return prev[-1]


def hero_in_candidates(catalog_hero, candidates):
    """Check whether the OCR captured the catalog's hero name in any
    of its candidates.

    Returns:
      - True  if a candidate matches the catalog hero (substring,
              prefix-overlap ≥4 on long tokens, OR Levenshtein ≤2 on
              letters-only normalized forms)
      - False if at least one candidate looks like a hero name (≥3
              letters) but NONE match the catalog hero — this is the
              wrong-image case (a different hero's art under the
              catalog row's slug)
      - None  if no candidate carries hero signal at all (OCR only
              captured the power glyph or junk fragments)
    """
    if not catalog_hero:
        return None
    target = catalog_hero.upper().strip()
    target_letters = _letters_only(target)
    target_tokens = {t for t in target.split() if len(t) >= 3 and not t.isdigit()}

    saw_alpha = False
    for cand in candidates:
        c = cand.upper().strip()
        letters = _letters_only(c)
        # Allow very-short letter strings (catalog has 2-letter heroes
        # like "A.I." / "X.L." whose letters-only form is just "AI"
        # or "XL"). The substring check below remains meaningful on
        # those — and skipping at <3 was causing legitimate matches
        # to fall through into the "wrong-image" bucket. Single-char
        # fragments are still skipped — too noisy.
        if len(letters) < 2:
            continue
        saw_alpha = True
        # 1. Direct substring on letters-only forms — handles missing
        #    apostrophes/hyphens/spaces ("MICDUP" vs "MIC'D UP",
        #    "AI" vs "AI" for "A.I.").
        if target_letters and (
            target_letters in letters or letters in target_letters
        ):
            return True
        # 2. Levenshtein on letters-only — handles multi-char OCR
        #    substitutions on stylized BoBA art ("GIGANTE" / "CIGANII"
        #    differs by 3 chars, "PEEK-A-BOO" / "PHEK" by ~6, etc.).
        #    Tolerance scales with hero length so short heroes stay
        #    strict while long ones absorb more noise — without that,
        #    char-substitution cards on Mixtape/Miami Ice art pile
        #    into the wrong-image bucket as false positives.
        if target_letters and len(target_letters) >= 3 and len(letters) >= 3:
            tolerance = max(1, len(target_letters) // 3)
            if _edit_distance(target_letters, letters, cap=tolerance) <= tolerance:
                return True
            # Same comparison with the shorter side wrapped — if the
            # OCR captured only a prefix of the hero (truncation), we
            # want a partial match. Compute distance from the OCR
            # candidate to the corresponding-length prefix of the
            # target.
            if len(letters) < len(target_letters):
                trunc_target = target_letters[: len(letters)]
                if _edit_distance(trunc_target, letters, cap=tolerance) <= tolerance:
                    return True
        # 3. Token-level: catalog-hero word in candidate word with
        #    prefix-overlap or containment.
        cand_tokens = {t for t in c.split() if len(t) >= 3 and any(ch.isalpha() for ch in t)}
        for tt in target_tokens:
            tt_letters = _letters_only(tt)
            for ct in cand_tokens:
                ct_letters = _letters_only(ct)
                if tt_letters and (tt_letters == ct_letters
                                    or tt_letters in ct_letters
                                    or ct_letters in tt_letters):
                    return True
                if len(tt_letters) >= 5 and len(ct_letters) >= 5:
                    overlap = 0
                    for a, b in zip(tt_letters, ct_letters):
                        if a == b:
                            overlap += 1
                        else:
                            break
                    if overlap >= 4:
                        return True
    return False if saw_alpha else None


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
        help="Master catalog — used for the hero-by-bobaId lookup that drives "
        "the wrong-image guard.",
    )
    ap.add_argument(
        "--confidence",
        type=float,
        default=0.85,
        help="Mismatches below this confidence go to needs_review.json instead of the patch",
    )
    ap.add_argument(
        "--max-delta",
        type=int,
        default=40,
        help=(
            "Mismatches with |ocrPower - catalogPower| > max-delta route to "
            "needs_review.json. Large deltas are dominated by wrong-image-on-R2 "
            "bugs (catalog row's slug points to a different hero's art) rather "
            "than wrong-power-in-catalog bugs; patching power on those would "
            "MIS-align the row with the wrong image. Conservative default 40."
        ),
    )
    ap.add_argument(
        "--min-ocr",
        type=int,
        default=100,
        help=(
            "Mismatches with ocrPower below this floor route to needs_review.json. "
            "Sub-100 OCR results are usually leading-digit-drop errors — Vision "
            "missed the '1' in '170' and returned '70'."
        ),
    )
    args = ap.parse_args()

    audit = json.loads(args.audit.read_text())
    rows = audit["results"]
    args.out_dir.mkdir(parents=True, exist_ok=True)

    # Load the catalog and build a bobaId → hero map. We can't reliably
    # derive `hero` from the bobaId string alone because cardNumbers
    # contain hyphens (e.g. "ABF-326") and heroes contain hyphens
    # (e.g. "Crews-Missle"), so a positional split mis-extracts. The
    # catalog JSON has the canonical hero per row.
    catalog = json.loads(args.catalog.read_text())
    hero_by_bid = {c["bobaId"]: (c.get("hero") or "")
                   for c in catalog if c.get("bobaId")}

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
        # Leading-digit-drop guard: if the catalog is 3-digit and OCR
        # is 2-digit AND the OCR matches the trailing digits of the
        # catalog, this is overwhelmingly an OCR error (the recognizer
        # missed the leading "1" on a 1XX power glyph). Verified
        # against ABF-149 Destroya — catalog 175, OCR 75, art shows
        # 175 ✓. 67 such suspects in the full audit; treating all as
        # OCR errors rather than catalog errors keeps the patch safe.
        if (
            cat is not None
            and ocr is not None
            and len(str(cat)) == 3
            and len(str(ocr)) == 2
            and str(cat).endswith(str(ocr))
        ):
            record["reason_filtered"] = "leading_digit_drop"
            needs_review.append(record)
            continue
        # Min-OCR floor — sub-100 OCRs are almost always glyph-recognition
        # failures, not real catalog overstatements.
        if ocr < args.min_ocr:
            record["reason_filtered"] = "ocr_below_floor"
            needs_review.append(record)
            continue
        # Max-delta filter — large gaps are dominated by wrong-image
        # bugs (the catalog row's imageFile points to a different
        # hero's art on R2). Patching power on those mis-aligns the
        # row with the wrong image; route to review instead.
        if delta is not None and abs(delta) > args.max_delta:
            record["reason_filtered"] = "delta_above_threshold"
            needs_review.append(record)
            continue
        # Hero-name verification guard. The OCR captures the printed
        # hero name as one of its candidates on most cards. If the
        # captured hero clearly DOES NOT match the catalog row's
        # hero, the image at this bobaId's slug is a wrong-image
        # collision (DECISIONS.md #026 territory) — patching the
        # power would corrupt the catalog row to align with the
        # wrong card's stats. Route to review instead. We accept
        # rows where OCR didn't capture a hero token at all (None
        # return) since on stylized cards the recognizer sometimes
        # only finds the power glyph; the confidence + delta gates
        # already filter most of those.
        catalog_hero = hero_by_bid.get(bid, "")
        hero_match = hero_in_candidates(catalog_hero, r.get("candidates", []))
        if hero_match is False:
            record["reason_filtered"] = "hero_mismatch_likely_wrong_image"
            needs_review.append(record)
            continue
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
