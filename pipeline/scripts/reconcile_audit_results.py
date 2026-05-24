#!/usr/bin/env python3
"""
reconcile_audit_results.py — Phase 4 of CARD_AUDIT_PIPELINE.md

Joins the OCR output from CardAuditCLI against cards.json, buckets
every card into CONFIRMS / UPDATES / REVIEW / NEEDS_IMAGE, and emits:

  - {out_dir}/patch.json     — Cowork-shaped patch with `modify[]`
                                entries for UPDATES bucket
  - {out_dir}/review.html    — Side-by-side human-review report for
                                low-confidence + ambiguous cards
  - {out_dir}/summary.json   — Per-bucket counts + per-field stats

Buckets:
  - CONFIRMS:    Every extracted field's high-conf OCR matches catalog.
  - UPDATES:     At least one high-confidence OCR DISAGREES with catalog
                  (catalog likely wrong; propose patch after human gate).
  - REVIEW:      One or more fields low-confidence or ambiguous
                  (OCR confidence below threshold, or OCR returned null
                  while catalog has a value, etc.).
  - NEEDS_IMAGE: Card has imageFile but OCR row missing — fetch failed
                  or image unreadable.

Confidence thresholds:
  - HIGH:   conf >= 0.85
  - MEDIUM: 0.50 <= conf < 0.85
  - LOW:    conf < 0.50

Usage:
    python3 pipeline/scripts/reconcile_audit_results.py \
        --catalog assets/data/cards.json \
        --ocr     ~/.boba-card-audit/ocr_results.json \
        --out     handoff-updates-2026-05-24/audit \
        [--cdn-base https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import unicodedata
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

CDN_BASE_DEFAULT = "https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev"

# Confidence floors.
HIGH_CONF = 0.85
MED_CONF = 0.50

# Minimum fraction of cards in a prefix bucket that must share one
# treatment for that prefix → treatment derivation to be "trusted".
# 0.95 keeps deterministic prefixes (ABF→Alpha Battlefoil at 100%,
# CHILL→Chillin' Battlefoil at 100%) while excluding ambiguous ones
# (BL → 17%-dominant Blue Blast, BLC → 33%-dominant Grape).
PREFIX_TREATMENT_THRESHOLD = 0.95


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--catalog", required=True)
    p.add_argument("--ocr", required=True)
    p.add_argument("--out", required=True,
                   help="Output directory (created if missing)")
    p.add_argument("--cdn-base", default=CDN_BASE_DEFAULT,
                   help="Override the R2 base URL for image links")
    p.add_argument("-v", "--verbose", action="store_true")
    return p.parse_args()


# Common Vision OCR digit↔letter confusions on stylized BoBA card
# glyphs. Used by normalize_card_number to fuzzy-match cardNumbers
# where the OCR returned a near-canonical form (e.g. "BLBF-Z" for
# "BLBF-2", "R8F-13" for "RBF-13", "CHILL-S" for "CHILL-5"). Both
# directions are mapped so normalization is symmetric.
OCR_DIGIT_LETTER_HOMOGLYPHS = str.maketrans({
    "O": "0", "o": "0",          # O ↔ 0
    "I": "1", "l": "1", "i": "1",  # I, l, i ↔ 1
    "Z": "2", "z": "2",          # Z ↔ 2  (BLBF-Z → BLBF-2)
    "S": "5", "s": "5",          # S ↔ 5  (CHILL-S → CHILL-5)
    "G": "6", "g": "6",          # G ↔ 6
    "B": "8", "b": "8",          # B ↔ 8  (R8F-13 prefix is RBF; also CHILL-B → CHILL-8)
    "T": "7",                    # T ↔ 7 (less common; e.g. "T-15" from "115")
})


def normalize_card_number(s: str | None) -> str:
    """Fuzzy-normalize a cardNumber for comparison: uppercase, strip
    punctuation, apply digit↔letter homoglyph map so common OCR
    confusions (B↔8, S↔5, etc.) compare equal. Preserves the
    PREFIX-NUMBER structure; only suffix digits are remapped.
    """
    if s is None:
        return ""
    raw = re.sub(r"[^A-Za-z0-9]", "", str(s)).upper()
    if not raw:
        return ""
    # Split into prefix (letters) and suffix (anything after).
    m = re.match(r"^([A-Z]+)(.*)$", raw)
    if not m:
        return raw.translate(OCR_DIGIT_LETTER_HOMOGLYPHS)
    prefix, suffix = m.group(1), m.group(2)
    return prefix + suffix.translate(OCR_DIGIT_LETTER_HOMOGLYPHS)


def normalize_text(s: str | None) -> str:
    """Strip accents, lowercase, drop non-alphanumeric. Used to compare
    OCR'd hero names against catalog where Vision's homoglyph
    behavior (Cyrillic О vs Latin O, etc.) creates spurious diffs."""
    if not s:
        return ""
    # Unicode-normalize then strip combining marks (NFKD).
    decomposed = unicodedata.normalize("NFKD", str(s))
    ascii_only = "".join(c for c in decomposed if not unicodedata.combining(c))
    # Map common Cyrillic → Latin lookalikes Vision returns.
    # Strict-equivalent characters (visually identical glyphs).
    homoglyphs = str.maketrans({
        "А": "A", "В": "B", "С": "C", "Е": "E", "Н": "H", "К": "K",
        "М": "M", "О": "O", "Р": "P", "Т": "T", "Х": "X",
        "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "х": "x",
    })
    ascii_only = ascii_only.translate(homoglyphs)
    return re.sub(r"[^A-Za-z0-9]", "", ascii_only).lower()


def field_status(ocr_value, ocr_conf: float, catalog_value,
                 *, ocr_extractable: bool = True) -> str:
    """Return one of: MATCH / MISMATCH / NULL_OCR / LOW_CONF / OK_NULL
    / NOT_EXTRACTABLE.

    OK_NULL         = both OCR and catalog have no value — no action.
    NOT_EXTRACTABLE = this catalog value's shape isn't expected to be
                      printed on the card art (e.g. Base Set bare-
                      digit cardNumbers like "1" or "47" — the number
                      is set-position metadata, not artwork). Drops
                      out of the REVIEW bucket so we don't drown the
                      report in false positives.

    Key policy: **agreement between OCR and catalog returns MATCH
    regardless of OCR confidence.** The match itself is the
    validation — low-confidence OCR that happens to land on the
    catalog value (after multi-pass voting + region scoring) is
    still corroboration. Only DISAGREEMENT needs high confidence to
    bucket as MISMATCH (since a confident-disagreement is what
    becomes a UPDATES patch); low-confidence disagreement is REVIEW.
    """
    if not ocr_extractable:
        return "NOT_EXTRACTABLE"
    if ocr_value is None or ocr_value == "":
        if catalog_value is None or catalog_value == "":
            return "OK_NULL"
        return "NULL_OCR"  # catalog has value, OCR didn't find one
    if normalize_text(ocr_value) == normalize_text(catalog_value):
        return "MATCH"
    # Disagreement: only flag as MISMATCH if OCR is confident enough
    # that the catalog is probably the one that's wrong.
    if ocr_conf < HIGH_CONF:
        return "LOW_CONF"
    return "MISMATCH"


# Bare-digit cardNumbers (1, 47, 115, …) are set-position metadata,
# not necessarily printed on the card art. Prefix-dash cardNumbers
# (ABF-100, BHBF-37) ARE printed and OCR-able. Tested empirically on
# the 600-card Hero pilot — every bare-digit cardNumber's bottom-strip
# OCR returned the trademark text instead of the digit.
def card_number_extractable(catalog_card_number) -> bool:
    if catalog_card_number is None:
        return False
    s = str(catalog_card_number)
    return bool(re.match(r"^[A-Z]{2,}", s))  # require 2+ letter prefix


def _card_number_status(ocr_value, ocr_conf: float, catalog_value) -> str:
    """cardNumber-specific status that applies OCR-confusion fuzzy
    matching (B↔8, S↔5, Z↔2, etc.) before declaring MISMATCH.

    Crucially: if OCR returned a prefix-dash-suffix string whose
    prefix doesn't match the catalog's prefix, that's irrelevant
    noise from elsewhere on the card (trademark text like "BO
    JACKSON" matched the relaxed extractor regex). Treat as
    NULL_OCR rather than MISMATCH so it doesn't pollute the
    UPDATES bucket."""
    if not card_number_extractable(catalog_value):
        return "NOT_EXTRACTABLE"
    if ocr_value is None or ocr_value == "":
        return "NULL_OCR"
    if normalize_card_number(ocr_value) == normalize_card_number(catalog_value):
        return "MATCH"
    # OCR found something but no fuzzy-match. Reject as noise if the
    # prefix doesn't match the catalog's prefix.
    cat_pref_m = re.match(r"^([A-Z]+)", str(catalog_value))
    ocr_pref_m = re.match(r"^([A-Z]+)", normalize_card_number(ocr_value))
    if not (cat_pref_m and ocr_pref_m and cat_pref_m.group(1) == ocr_pref_m.group(1)):
        return "NULL_OCR"
    if ocr_conf < HIGH_CONF:
        return "LOW_CONF"
    return "MISMATCH"


def power_status(ocr_int, ocr_conf: float, catalog_int) -> str:
    if ocr_int is None:
        return "OK_NULL" if catalog_int is None else "NULL_OCR"
    if ocr_int == catalog_int:
        return "MATCH"  # agreement = corroboration; conf doesn't matter
    if ocr_conf < HIGH_CONF:
        return "LOW_CONF"
    return "MISMATCH"


def bucket_for(statuses: dict[str, str]) -> str:
    """Roll up per-field statuses into one of CONFIRMS / UPDATES / REVIEW.
    NOT_EXTRACTABLE rows are treated as OK_NULL — they don't block CONFIRMS."""
    if any(s == "MISMATCH" for s in statuses.values()):
        return "UPDATES"
    if any(s in {"LOW_CONF", "NULL_OCR"} for s in statuses.values()):
        return "REVIEW"
    return "CONFIRMS"


def build_prefix_treatment_map(catalog: list[dict]) -> dict[str, str]:
    """Survey catalog for prefix → dominant-treatment. Returns only
    prefixes where the dominant treatment covers ≥ PREFIX_TREATMENT_
    THRESHOLD of cards (so we don't propose UPDATES on prefixes where
    treatment genuinely varies, like BL → both Blue Blast + others)."""
    counts: dict[str, Counter] = {}
    for c in catalog:
        if c.get("cardType") != "Hero":
            continue
        cn = c.get("cardNumber", "") or ""
        tr = c.get("treatment")
        if not cn or not tr:
            continue
        m = re.match(r"^([A-Z]+)-", cn)
        if not m:
            continue
        counts.setdefault(m.group(1), Counter())[tr] += 1
    out: dict[str, str] = {}
    for prefix, ctr in counts.items():
        total = sum(ctr.values())
        top, top_n = ctr.most_common(1)[0]
        if top_n / total >= PREFIX_TREATMENT_THRESHOLD:
            out[prefix] = top
    return out


def derive_treatment(card_number: str | None,
                     prefix_map: dict[str, str]) -> str | None:
    """Return the prefix-derived treatment for this card, or None if
    the prefix isn't in the trusted map. Used to flag catalogs whose
    treatment field disagrees with what the cardNumber prefix says."""
    if not card_number:
        return None
    m = re.match(r"^([A-Z]+)-", str(card_number))
    if not m:
        return None
    return prefix_map.get(m.group(1))


def reconcile(catalog: list[dict], ocr_results: list[dict],
              cdn_base: str) -> dict:
    catalog_by_id = {c["bobaId"]: c for c in catalog if c.get("bobaId")}
    ocr_by_id = {r["bobaId"]: r for r in ocr_results if r.get("bobaId")}
    prefix_treatment_map = build_prefix_treatment_map(catalog)

    confirms, updates, review = [], [], []
    needs_image = []
    per_field_stats: dict[str, Counter] = {
        f: Counter() for f in ("cardNumber", "name", "power", "serial", "element", "treatment")
    }

    for card in catalog:
        bid = card.get("bobaId")
        if not bid or not card.get("imageFile"):
            continue
        row = ocr_by_id.get(bid)
        if row is None:
            needs_image.append(bid)
            continue

        ocr = row["ocr"]
        statuses = {
            "cardNumber": _card_number_status(
                ocr["cardNumber"].get("value"),
                ocr["cardNumber"].get("confidence", 0.0),
                card.get("cardNumber"),
            ),
            "name": field_status(
                ocr["name"].get("value"),
                ocr["name"].get("confidence", 0.0),
                card.get("name") or card.get("hero"),
            ),
            "power": power_status(
                ocr["power"].get("intValue"),
                ocr["power"].get("confidence", 0.0),
                card.get("power"),
            ) if card.get("cardType") == "Hero" else "NOT_EXTRACTABLE",
            # Serial is INFORMATIONAL — catalog doesn't store the
            # printed serial number, only the isInspiredInk boolean.
            # The OCR'd serial gets surfaced in the audit row for
            # human reference (e.g. verifying that IK denominators
            # follow the Hex /5, Glow /10, Fire /25, Ice /50 rule per
            # DECISIONS.md #028), but doesn't drive a match/mismatch
            # status. Cross-check happens in the HTML review report.
            "serial": "NOT_EXTRACTABLE",
            "element": field_status(
                (ocr.get("element") or {}).get("value"),
                (ocr.get("element") or {}).get("confidence", 0.0),
                card.get("element"),
            ),
            # Treatment is derived from cardNumber prefix (which IS
            # printed on the card art), not OCR'd separately. Confidence
            # is implicitly 1.0 for trusted prefixes (≥95% catalog-
            # consistent) and NOT_EXTRACTABLE for ambiguous ones (BL,
            # BLC, SK where the prefix maps to multiple treatments).
            "treatment": field_status(
                derive_treatment(card.get("cardNumber"), prefix_treatment_map),
                1.0,
                card.get("treatment"),
                ocr_extractable=derive_treatment(
                    card.get("cardNumber"), prefix_treatment_map) is not None,
            ),
        }
        for f, s in statuses.items():
            per_field_stats[f][s] += 1

        bucket = bucket_for(statuses)
        entry = {
            "bobaId": bid,
            "imageFile": card["imageFile"],
            "cardType": card.get("cardType"),
            "statuses": statuses,
            "catalog": {
                "cardNumber": card.get("cardNumber"),
                "name": card.get("name") or card.get("hero"),
                "power": card.get("power"),
                "element": card.get("element"),
                "treatment": card.get("treatment"),
                "isInspiredInk": card.get("isInspiredInk"),
            },
            "ocr": {
                "cardNumber": ocr["cardNumber"],
                "name": ocr["name"],
                "power": ocr["power"],
                "serial": ocr["serial"],
            },
            "image_url": f"{cdn_base}/full/{card['imageFile']}",
        }
        if bucket == "CONFIRMS":
            confirms.append(entry)
        elif bucket == "UPDATES":
            updates.append(entry)
        else:
            review.append(entry)

    return {
        "confirms": confirms,
        "updates": updates,
        "review": review,
        "needs_image": needs_image,
        "per_field_stats": per_field_stats,
    }


def build_patch(updates: list[dict], all_rows: list[dict] | None = None) -> dict:
    """Cowork-format patch: modify[] entries with old_bobaId + changes
    + evidence. apply_handoff_batch.py understands this shape.

    Also generates an `additions[]` section for printed-serial values
    extracted from Inspired Ink card art — per Ben's directive that
    "relying upon what is written on the card is a much better way to
    go" (the IK denominator-element rule has exceptions, so the
    printed serial is the authoritative source). The catalog gains a
    new `printedSerial` field. Apply this section after the modify
    section.
    """
    modify = []
    for u in updates:
        changes = {}
        evidence = {}
        for field, status in u["statuses"].items():
            if status != "MISMATCH":
                continue
            ocr_field = u.get("ocr", {}).get(field) or {}
            if field == "cardNumber":
                changes["cardNumber"] = ocr_field.get("value")
            elif field == "name":
                changes["name"] = ocr_field.get("value")
            elif field == "power":
                changes["power"] = ocr_field.get("intValue")
            elif field == "element":
                changes["element"] = ocr_field.get("value")
            elif field == "treatment":
                changes["treatment"] = u["catalog"].get("_derived_treatment")
            elif field == "serial":
                continue
            evidence[field] = {
                "ocr_value": ocr_field.get("value")
                             if field not in {"power"}
                             else ocr_field.get("intValue"),
                "ocr_confidence": ocr_field.get("confidence"),
                "catalog_value": u["catalog"].get(field),
            }
        if changes:
            modify.append({
                "old_bobaId": u["bobaId"],
                "changes": changes,
                "evidence": evidence,
            })

    # Printed-serial additions — every IK card where OCR extracted a
    # /N serial (e.g. "15/25"). Rule conflicts (printed denominator
    # disagrees with the IK rule for catalog element) are surfaced as
    # `rule_conflict: true` so humans can decide whether the catalog
    # element is wrong or there's a real exception.
    additions = []
    rule_denom_for_element = {"HEX": 5, "GLOW": 10, "FIRE": 25, "ICE": 50}
    for u in (all_rows or []):
        if not u["catalog"].get("isInspiredInk"):
            continue
        serial = (u.get("ocr", {}).get("serial") or {}).get("value")
        if not serial:
            continue
        serial_denom = (u.get("ocr", {}).get("serial") or {}).get("intValue")
        element = u["catalog"].get("element")
        expected_denom = rule_denom_for_element.get(element)
        rule_conflict = bool(expected_denom and serial_denom and expected_denom != serial_denom)
        additions.append({
            "old_bobaId": u["bobaId"],
            "additions": {"printedSerial": serial},
            "evidence": {
                "printedSerial": {
                    "ocr_value": serial,
                    "ocr_denominator": serial_denom,
                    "catalog_element": element,
                    "rule_expected_denominator": expected_denom,
                    "rule_conflict": rule_conflict,
                }
            },
        })

    return {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": "card_audit_pipeline",
        "modify": modify,
        "additions": additions,
    }


def build_review_html(review: list[dict], updates: list[dict]) -> str:
    """Side-by-side image + extracted vs catalog. Human walks the
    list; opening a card's image in a browser tab is one click away."""
    def row_html(e: dict, kind: str) -> str:
        statuses_html = ""
        for f, s in e["statuses"].items():
            cat = e["catalog"].get(f) if f != "serial" else "—"
            ocr_field = e.get("ocr", {}).get(f) or {}
            if f == "power":
                ocr = ocr_field.get("intValue")
            else:
                ocr = ocr_field.get("value")
            conf = ocr_field.get("confidence", 0)
            color = {"MATCH": "#4CAF50", "MISMATCH": "#FF4D00",
                     "LOW_CONF": "#FFC107", "NULL_OCR": "#9E9E9E",
                     "OK_NULL": "#9E9E9E"}.get(s, "#fff")
            statuses_html += (
                f"<tr><td>{f}</td><td>{cat!r}</td>"
                f"<td>{ocr!r}</td>"
                f"<td>{conf:.2f}</td>"
                f"<td style='color:{color};font-weight:700'>{s}</td></tr>"
            )
        return f"""
            <div class="card-row" data-kind="{kind}" data-boba="{e['bobaId']}">
              <img src="{e['image_url']}" loading="lazy" />
              <div class="meta">
                <h3>{e['bobaId']}</h3>
                <div class="cardtype">{e['cardType']}</div>
                <table>
                  <thead><tr><th>field</th><th>catalog</th>
                  <th>ocr</th><th>conf</th><th>status</th></tr></thead>
                  <tbody>{statuses_html}</tbody>
                </table>
              </div>
            </div>"""
    body = "\n".join(row_html(e, "UPDATES") for e in updates) + \
           "\n".join(row_html(e, "REVIEW") for e in review)
    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>Card Audit Review</title>
<style>
  body {{ background: #080810; color: #fff;
          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
          padding: 24px; }}
  h1 {{ font-size: 28px; }}
  .legend {{ margin: 16px 0; opacity: 0.8; }}
  .legend span {{ margin-right: 12px; padding: 2px 8px; border-radius: 4px; }}
  .card-row {{ display: flex; gap: 16px; margin-bottom: 24px;
              padding: 16px; background: #0D0D1A;
              border: 1px solid rgba(255,255,255,0.1); border-radius: 8px; }}
  .card-row img {{ width: 200px; height: auto; align-self: flex-start;
                  border-radius: 6px; }}
  .meta {{ flex: 1; }}
  .meta h3 {{ margin: 0 0 4px; font-size: 16px; font-family: monospace; }}
  .cardtype {{ font-size: 12px; opacity: 0.6; margin-bottom: 8px; }}
  table {{ width: 100%; font-size: 13px; border-collapse: collapse; }}
  th, td {{ text-align: left; padding: 4px 8px;
            border-bottom: 1px solid rgba(255,255,255,0.05); }}
  th {{ font-size: 11px; opacity: 0.5; text-transform: uppercase;
        font-weight: normal; }}
  td:nth-child(2), td:nth-child(3) {{ font-family: monospace; font-size: 12px; }}
  [data-kind=UPDATES] {{ border-left: 4px solid #FF4D00; }}
  [data-kind=REVIEW] {{ border-left: 4px solid #FFC107; }}
</style>
</head><body>
<h1>Card Audit Review</h1>
<p class="legend">
  <span style="background:#FF4D00">UPDATES ({len(updates)})</span>
  <span style="background:#FFC107;color:#000">REVIEW ({len(review)})</span>
</p>
<p>UPDATES are catalog rows where high-confidence OCR disagrees with
the stored value — proposed patches that need human ratification before
they hit cards.json. REVIEW rows are low-confidence or ambiguous cases
where the audit can't decide.</p>
{body}
</body></html>"""


def main() -> int:
    args = parse_args()
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    with open(args.catalog) as f:
        catalog = json.load(f)
    with open(args.ocr) as f:
        ocr_doc = json.load(f)
    ocr_results = ocr_doc.get("results", [])

    print(f"[reconcile] catalog={len(catalog)} cards, ocr_rows={len(ocr_results)}",
          flush=True)
    bundle = reconcile(catalog, ocr_results, args.cdn_base)

    summary = {
        "ran_at": datetime.now(timezone.utc).isoformat(),
        "buckets": {
            "confirms": len(bundle["confirms"]),
            "updates": len(bundle["updates"]),
            "review": len(bundle["review"]),
            "needs_image": len(bundle["needs_image"]),
        },
        "per_field_stats": {
            f: dict(c) for f, c in bundle["per_field_stats"].items()
        },
    }

    # Emit outputs. Patch includes both modify[] (catalog corrections)
    # and additions[] (printed-serial captures for every IK card).
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    all_rows = bundle["confirms"] + bundle["updates"] + bundle["review"]
    patch = build_patch(bundle["updates"], all_rows=all_rows)
    (out_dir / "patch.json").write_text(json.dumps(patch, indent=2))
    review_html = build_review_html(bundle["review"], bundle["updates"])
    (out_dir / "review.html").write_text(review_html)

    print(f"[reconcile] CONFIRMS:    {summary['buckets']['confirms']}")
    print(f"[reconcile] UPDATES:     {summary['buckets']['updates']}  → patch.json (modify[])")
    print(f"[reconcile] REVIEW:      {summary['buckets']['review']}  → review.html")
    print(f"[reconcile] NEEDS_IMAGE: {summary['buckets']['needs_image']}")
    n_additions = len(patch.get("additions", []))
    n_rule_conflicts = sum(
        1 for a in patch.get("additions", [])
        if a["evidence"]["printedSerial"].get("rule_conflict")
    )
    if n_additions:
        print(f"[reconcile] PRINTED_SERIAL additions: {n_additions} "
              f"({n_rule_conflicts} with IK rule conflict) → patch.json (additions[])")
    print()
    print("[reconcile] Per-field status counts:")
    for f, stats in summary["per_field_stats"].items():
        items = ", ".join(f"{k}={v}" for k, v in sorted(stats.items()))
        print(f"  {f:<14} {items}")
    print()
    print(f"[reconcile] outputs → {out_dir}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
