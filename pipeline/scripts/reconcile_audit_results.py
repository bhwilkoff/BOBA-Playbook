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
from urllib.parse import quote

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
                "hero": card.get("hero"),
                "variation": card.get("variation"),
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
            # Percent-encode the imageFile so non-ASCII chars
            # (Éric, Curaçao, Adrián, Martínez, etc.) become valid R2
            # URLs. The fetcher script hits this same problem and
            # skips those cards; the browser is stricter about URL
            # encoding than the Python urllib.
            "image_url": f"{cdn_base}/full/{quote(card['imageFile'], safe='._-')}",
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
            "image_url": u.get("image_url"),  # so the review HTML can show the card
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


def build_review_html(review: list[dict], updates: list[dict],
                       additions: list[dict] | None = None) -> str:
    """Interactive review tool — no server required. Three sections:

      UPDATES — proposed catalog corrections. Per change: Approve /
                Keep catalog / Edit-then-approve. Default = unapproved.
      REVIEW  — low-conf cards. Per field: optional manual override.
      ADDITIONS — new printedSerial values for IK cards. Per card:
                Approve / Skip / Edit. Most should be auto-approved
                since OCR found a value that wasn't in catalog before.

    State persists to localStorage (per-bobaId-per-field decisions
    survive page reloads). 'Export curated patch' button downloads
    the filtered patch.json to apply via apply_handoff_batch.py."""

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "updates": updates,
        "review": review,
        "additions": additions or [],
    }
    payload_json = json.dumps(payload, ensure_ascii=False)
    return r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Card Audit Review</title>
<style>
  * { box-sizing: border-box; }
  body { background: #080810; color: #fff;
         font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
         margin: 0; padding: 0; }
  header { position: sticky; top: 0; z-index: 10; background: rgba(13,13,26,0.95);
           backdrop-filter: blur(8px); padding: 16px 24px;
           border-bottom: 1px solid rgba(255,255,255,0.1); }
  header h1 { margin: 0 0 8px; font-size: 22px; }
  .stats { display: flex; gap: 16px; flex-wrap: wrap; align-items: center;
           font-size: 13px; }
  .stats .chip { padding: 4px 10px; border-radius: 999px; background: rgba(255,255,255,0.06); }
  .stats .chip strong { color: #00F5FF; }
  .controls { display: flex; gap: 8px; margin-top: 12px; flex-wrap: wrap; }
  .controls button, .controls select, .controls input {
    background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.15);
    color: #fff; padding: 6px 14px; border-radius: 6px;
    font-family: inherit; font-size: 13px; cursor: pointer;
  }
  .controls button:hover { background: rgba(255,255,255,0.12); }
  .controls .primary { background: #FF4D00; border-color: #FF4D00; }
  .controls .primary:hover { background: #ff6022; }
  .controls input[type="search"] { width: 220px; }

  main { padding: 24px; max-width: 1400px; margin: 0 auto; }
  .section { margin-bottom: 40px; }
  .section h2 { font-size: 16px; opacity: 0.7; text-transform: uppercase;
                letter-spacing: 0.08em; margin: 0 0 16px;
                border-bottom: 1px solid rgba(255,255,255,0.1); padding-bottom: 8px; }

  .card-row { display: flex; gap: 20px; margin-bottom: 20px;
              padding: 16px; background: #0D0D1A;
              border: 1px solid rgba(255,255,255,0.1); border-radius: 10px;
              transition: opacity 0.2s, border-color 0.2s; }
  .card-row.dismissed { opacity: 0.35; }
  .card-row.has-approval { border-color: rgba(76,175,80,0.5); }
  .card-row img { width: 180px; height: auto; align-self: flex-start;
                  border-radius: 6px; background: #000; cursor: zoom-in; }
  .meta { flex: 1; min-width: 0; }
  .meta-head { display: flex; justify-content: space-between; align-items: baseline;
               gap: 12px; margin-bottom: 8px; }
  .meta h3 { margin: 0; font-size: 14px; font-family: ui-monospace, monospace;
             color: #00F5FF; word-break: break-all; }
  .cardtype { font-size: 11px; opacity: 0.5; padding: 2px 8px; border-radius: 4px;
              background: rgba(255,255,255,0.05); white-space: nowrap; }

  .field-table { width: 100%; font-size: 13px; border-collapse: collapse; }
  .field-table th { font-size: 10px; opacity: 0.4; text-transform: uppercase;
                    text-align: left; padding: 4px 8px; font-weight: 500; }
  .field-table td { padding: 6px 8px; border-bottom: 1px solid rgba(255,255,255,0.05);
                    vertical-align: middle; }
  .field-table .field-name { font-family: ui-monospace, monospace; opacity: 0.7;
                              font-size: 12px; }
  .field-table .val { font-family: ui-monospace, monospace; font-size: 12px;
                       padding: 2px 6px; border-radius: 3px;
                       background: rgba(255,255,255,0.04); }
  .field-table .val.cat { color: #aab; }
  .field-table .val.ocr { color: #00F5FF; }
  .field-table .conf { font-size: 11px; opacity: 0.5; }
  .field-table .status { font-size: 10px; font-weight: 700; padding: 2px 6px;
                         border-radius: 3px; text-transform: uppercase; }
  .status.MATCH    { color: #4CAF50; background: rgba(76,175,80,0.1); }
  .status.MISMATCH { color: #FF4D00; background: rgba(255,77,0,0.12); }
  .status.LOW_CONF { color: #FFC107; background: rgba(255,193,7,0.1); }
  .status.NULL_OCR { color: #888;    background: rgba(255,255,255,0.04); }
  .status.OK_NULL  { color: #888;    background: rgba(255,255,255,0.04); }
  .status.NOT_EXTRACTABLE { color: #888; background: rgba(255,255,255,0.04); }

  .actions { display: flex; gap: 6px; flex-wrap: wrap; }
  .actions button {
    background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.15);
    color: #fff; padding: 3px 10px; border-radius: 4px;
    font-family: inherit; font-size: 11px; cursor: pointer;
  }
  .actions button:hover { background: rgba(255,255,255,0.14); }
  .actions button.active.approve { background: #4CAF50; border-color: #4CAF50; }
  .actions button.active.reject  { background: #777;    border-color: #777; }
  .actions input[type="text"], .actions input[type="number"] {
    background: rgba(0,245,255,0.06); border: 1px solid rgba(0,245,255,0.3);
    color: #00F5FF; font-family: ui-monospace, monospace; font-size: 12px;
    padding: 3px 6px; border-radius: 4px; width: 100px;
  }

  /* Card-level approve-all toggle */
  .row-foot { display: flex; gap: 8px; align-items: center; margin-top: 10px;
              padding-top: 10px; border-top: 1px solid rgba(255,255,255,0.05); }
  .row-foot button { font-size: 11px; padding: 4px 10px; cursor: pointer;
                     background: rgba(0,245,255,0.08); color: #00F5FF;
                     border: 1px solid rgba(0,245,255,0.3); border-radius: 4px; }
  .row-foot button:hover { background: rgba(0,245,255,0.16); }
  .row-foot .dismiss { background: rgba(255,255,255,0.04); color: #888;
                       border-color: rgba(255,255,255,0.1); margin-left: auto; }
  .row-foot .progress { font-size: 11px; opacity: 0.6; }

  .empty { padding: 40px; text-align: center; opacity: 0.5; font-style: italic; }

  .toast { position: fixed; bottom: 24px; left: 50%; transform: translateX(-50%);
           background: #0D0D1A; border: 1px solid rgba(0,245,255,0.4);
           padding: 10px 16px; border-radius: 6px; font-size: 13px;
           color: #00F5FF; opacity: 0; transition: opacity 0.2s;
           pointer-events: none; z-index: 100; }
  .toast.show { opacity: 1; }
</style>
</head><body>
<header>
  <h1>Card Audit Review</h1>
  <div class="stats" id="stats"></div>
  <div class="controls">
    <input type="search" id="search" placeholder="Filter (bobaId, hero, field…)" />
    <select id="filter-bucket">
      <option value="all">All buckets</option>
      <option value="UPDATES">UPDATES only</option>
      <option value="REVIEW">REVIEW only</option>
      <option value="ADDITIONS">ADDITIONS only</option>
    </select>
    <select id="filter-field">
      <option value="">All fields</option>
      <option value="power">power</option>
      <option value="name">name</option>
      <option value="cardNumber">cardNumber</option>
      <option value="element">element</option>
      <option value="treatment">treatment</option>
      <option value="printedSerial">printedSerial</option>
    </select>
    <select id="filter-status">
      <option value="">All states</option>
      <option value="pending">Pending decisions</option>
      <option value="approved">Approved</option>
      <option value="rejected">Rejected / kept catalog</option>
    </select>
    <label style="display:inline-flex;align-items:center;gap:6px;padding:4px 10px;border:1px solid rgba(0,245,255,0.4);border-radius:6px;cursor:pointer">
      <input type="checkbox" id="hide-decided" checked>
      Hide decided rows
    </label>
    <button id="approve-visible-ocr">Approve all visible OCR values</button>
    <button id="reject-visible">Keep catalog for all visible</button>
    <button class="primary" id="export">Export curated patch.json</button>
    <button id="reset" title="Clear all decisions stored in localStorage">Reset</button>
  </div>
</header>
<main>
  <section class="section" id="section-additions">
    <h2 id="head-additions">PRINTED_SERIAL additions — new catalog field</h2>
    <div id="list-additions"></div>
  </section>
  <section class="section" id="section-updates">
    <h2 id="head-updates">UPDATES — catalog likely wrong</h2>
    <div id="list-updates"></div>
  </section>
  <section class="section" id="section-review">
    <h2 id="head-review">REVIEW — low confidence, manual override only</h2>
    <div id="list-review"></div>
  </section>
</main>
<div class="toast" id="toast"></div>

<script id="audit-payload" type="application/json">__PAYLOAD__</script>
<script>
(function() {
  const PAYLOAD = JSON.parse(document.getElementById('audit-payload').textContent);
  const LS_KEY = 'boba-audit-decisions-v1';
  // Decisions shape: { "<bobaId>:<field>": { action: "approve"|"reject", value: "..." } }
  // For UPDATES, default is no decision → not in exported patch.
  // For ADDITIONS, default is approve (using OCR value).
  let decisions = {};
  try { decisions = JSON.parse(localStorage.getItem(LS_KEY) || '{}'); } catch (e) {}

  const $ = id => document.getElementById(id);
  const escapeHtml = s => String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

  function decisionKey(boba, field) { return boba + ':' + field; }
  function getDecision(boba, field) { return decisions[decisionKey(boba, field)]; }
  function setDecision(boba, field, action, value) {
    const k = decisionKey(boba, field);
    if (action == null) {
      delete decisions[k];
    } else {
      decisions[k] = { action, value };
    }
    persist();
    updateStats();
    updateRowState(boba);
    scheduleApplyFilters();
  }
  // Debounce applyFilters via rAF so a bulk loop (approve-row, R-key
  // hitting N fields, "approve-visible") only does one full DOM walk.
  let _filterScheduled = false;
  function scheduleApplyFilters() {
    if (_filterScheduled) return;
    _filterScheduled = true;
    requestAnimationFrame(() => {
      _filterScheduled = false;
      if (typeof applyFilters === 'function') applyFilters();
    });
  }
  function persist() {
    try { localStorage.setItem(LS_KEY, JSON.stringify(decisions)); }
    catch (e) { toast('Failed to save: ' + e.message); }
  }
  function toast(msg) {
    const el = $('toast'); el.textContent = msg; el.classList.add('show');
    clearTimeout(toast._t);
    toast._t = setTimeout(() => el.classList.remove('show'), 2200);
  }

  // For ADDITIONS, the default action is APPROVE — OCR found a value
  // that wasn't in catalog before, so we want to add it unless the
  // user explicitly rejects.
  function effectiveAction(boba, field, defaultApprove) {
    const d = getDecision(boba, field);
    if (d) return d.action;
    return defaultApprove ? 'approve' : null;
  }
  function effectiveValue(boba, field, ocrValue) {
    const d = getDecision(boba, field);
    if (d && d.value != null && d.value !== '') return d.value;
    return ocrValue;
  }

  // ============ RENDER ============
  //
  // Chunked rendering — building all 2,475 card-rows + their tables +
  // buttons in one synchronous burst froze the browser. New approach:
  // render the first CHUNK_SIZE rows immediately, then IntersectionObserver
  // appends another chunk every time the bottom sentinel scrolls into view.
  // Same pattern as the Collection grid in the web app (DECISIONS.md #020
  // / WEB-DESIGN.md note). Each chunk is a single DOM-attach batch so
  // layout cost is bounded.
  const CHUNK_SIZE = 40;
  const sectionState = { updates: null, review: null, additions: null };

  function renderChunkedSection(kind, items, builderFn) {
    const host = $('list-' + kind);
    host.innerHTML = '';
    const sentinel = host.appendChild(document.createElement('div'));
    sentinel.className = 'chunk-sentinel';
    sentinel.style.height = '20px';
    const state = { rendered: 0, items, builder: builderFn, sentinel, host };
    sectionState[kind] = state;
    if (!items.length) {
      host.innerHTML = '<div class="empty">No entries in this section.</div>';
      return;
    }
    appendChunk(kind);  // initial chunk
    // Observe the sentinel — append more whenever it enters viewport.
    const observer = new IntersectionObserver((entries) => {
      if (!entries[0].isIntersecting) return;
      if (state.rendered >= state.items.length) {
        observer.disconnect();
        sentinel.remove();
        return;
      }
      appendChunk(kind);
    }, { rootMargin: '600px 0px' });
    observer.observe(sentinel);
    state.observer = observer;
  }

  function appendChunk(kind) {
    const s = sectionState[kind];
    if (!s) return;
    const next = Math.min(s.rendered + CHUNK_SIZE, s.items.length);
    // Build into a fragment so layout happens once.
    const frag = document.createDocumentFragment();
    for (let i = s.rendered; i < next; i++) {
      frag.appendChild(s.builder(s.items[i]));
    }
    s.host.insertBefore(frag, s.sentinel);
    s.rendered = next;
    applyFiltersToSection(kind);
  }

  function renderUpdates() {
    renderChunkedSection('updates', PAYLOAD.updates, buildUpdatesRow);
    if (!PAYLOAD.updates.length) {
      $('list-updates').innerHTML = '<div class="empty">No UPDATES — no catalog corrections proposed.</div>';
    }
  }

  function buildUpdatesRow(e) {
    const div = document.createElement('div');
    div.className = 'card-row';
    div.dataset.kind = 'UPDATES';
    div.dataset.boba = e.bobaId;
    let rowsHtml = '';
    for (const [field, status] of Object.entries(e.statuses)) {
      if (field === 'serial') continue;
      const ocrField = (e.ocr && e.ocr[field]) || {};
      const ocrVal = field === 'power' ? ocrField.intValue : ocrField.value;
      const catVal = e.catalog[field];
      const conf = ocrField.confidence;
      const isProposed = (status === 'MISMATCH');
      rowsHtml += renderFieldRow(e.bobaId, field, catVal, ocrVal, conf, status, isProposed, false);
    }
    const fieldNames = Object.keys(e.statuses).filter(f => e.statuses[f] === 'MISMATCH');
    div.innerHTML = `
      <img src="${escapeHtml(e.image_url)}" loading="lazy" alt="${escapeHtml(e.bobaId)}" />
      <div class="meta">
        <div class="meta-head">
          <h3>${escapeHtml(e.bobaId)}</h3>
          <span class="cardtype">${escapeHtml(e.cardType || '')}</span>
        </div>
        <table class="field-table">
          <thead><tr><th>field</th><th>catalog</th><th>ocr (proposed)</th>
            <th>conf</th><th>state</th><th>decision</th></tr></thead>
          <tbody>${rowsHtml}</tbody>
        </table>
        <div class="row-foot">
          <button data-act="approve-row">Approve all OCR for this card</button>
          <button data-act="reject-row">Keep catalog for this card</button>
          <button class="dismiss" data-act="dismiss">Skip (already reviewed)</button>
        </div>
      </div>`;
    wireRow(div, e, fieldNames, false);
    return div;
  }

  function renderReview() {
    renderChunkedSection('review', PAYLOAD.review, buildReviewRow);
    if (!PAYLOAD.review.length) {
      $('list-review').innerHTML = '<div class="empty">No REVIEW cards.</div>';
    }
  }

  function buildReviewRow(e) {
    const div = document.createElement('div');
    div.className = 'card-row';
    div.dataset.kind = 'REVIEW';
    div.dataset.boba = e.bobaId;
    let rowsHtml = '';
    for (const [field, status] of Object.entries(e.statuses)) {
      if (field === 'serial') continue;
      const ocrField = (e.ocr && e.ocr[field]) || {};
      const ocrVal = field === 'power' ? ocrField.intValue : ocrField.value;
      const catVal = e.catalog[field];
      const conf = ocrField.confidence;
      // REVIEW cards have no proposed change by default; user can opt in.
      const userCanEdit = (status === 'LOW_CONF' || status === 'NULL_OCR');
      rowsHtml += renderFieldRow(e.bobaId, field, catVal, ocrVal, conf, status, false, userCanEdit);
    }
    div.innerHTML = `
      <img src="${escapeHtml(e.image_url)}" loading="lazy" alt="${escapeHtml(e.bobaId)}" />
      <div class="meta">
        <div class="meta-head">
          <h3>${escapeHtml(e.bobaId)}</h3>
          <span class="cardtype">${escapeHtml(e.cardType || '')}</span>
        </div>
        <table class="field-table">
          <thead><tr><th>field</th><th>catalog</th><th>ocr</th>
            <th>conf</th><th>state</th><th>decision</th></tr></thead>
          <tbody>${rowsHtml}</tbody>
        </table>
        <div class="row-foot">
          <button class="dismiss" data-act="dismiss">Skip (no change)</button>
        </div>
      </div>`;
    wireRow(div, e, [], true);
    return div;
  }

  function renderAdditions() {
    renderChunkedSection('additions', PAYLOAD.additions, buildAdditionsRow);
    if (!PAYLOAD.additions.length) {
      $('list-additions').innerHTML = '<div class="empty">No printedSerial additions — no IK cards had a serial extracted.</div>';
    }
  }

  function buildAdditionsRow(e) {
    const div = document.createElement('div');
    div.className = 'card-row';
    div.dataset.kind = 'ADDITIONS';
    div.dataset.boba = e.old_bobaId;
    const ev = e.evidence.printedSerial;
    const val = e.additions.printedSerial;
    // Python embedded the image_url for every IK card alongside the
    // serial extraction. Fall back to the catalog map only if missing
    // (older patch.json schemas).
    const cardImageUrl = e.image_url
      || (PAYLOAD.updates.concat(PAYLOAD.review).find(r => r.bobaId === e.old_bobaId) || {}).image_url
      || '';
    const conflict = ev.rule_conflict;
    const noteStyle = conflict ? 'color:#FFC107' : 'color:#888';
    const note = conflict
      ? `Catalog says element=${ev.catalog_element} (IK rule → /${ev.rule_expected_denominator}); printed = /${ev.ocr_denominator}.`
      : `Matches IK rule (element=${ev.catalog_element} → /${ev.rule_expected_denominator}).`;
    div.innerHTML = `
      <img src="${escapeHtml(cardImageUrl)}" loading="lazy" alt="${escapeHtml(e.old_bobaId)}" />
      <div class="meta">
        <div class="meta-head">
          <h3>${escapeHtml(e.old_bobaId)}</h3>
          <span class="cardtype">IK · printedSerial</span>
        </div>
        <table class="field-table">
          <thead><tr><th>field</th><th>catalog</th><th>ocr</th>
            <th>conf</th><th>state</th><th>decision</th></tr></thead>
          <tbody>${renderFieldRow(e.old_bobaId, 'printedSerial', '(none)', val, 1.0, 'MISMATCH', true, false, true)}</tbody>
        </table>
        <div style="font-size:12px; margin-top:8px; ${noteStyle}">${escapeHtml(note)}</div>
      </div>`;
    wireRow(div, { bobaId: e.old_bobaId }, ['printedSerial'], false, /*defaultApprove=*/true);
    return div;
  }

  function renderFieldRow(boba, field, catVal, ocrVal, conf, status, isProposed, userCanEdit, defaultApprove) {
    const confDisplay = (typeof conf === 'number') ? conf.toFixed(2) : '—';
    const isEditable = isProposed || userCanEdit || defaultApprove;
    const actCellId = `act-${boba.replace(/[^A-Za-z0-9]/g, '_')}-${field}`;
    let actionsHtml = '';
    if (isEditable) {
      const inputVal = effectiveValue(boba, field, ocrVal == null ? '' : ocrVal);
      const inputType = field === 'power' ? 'number' : 'text';
      actionsHtml = `
        <div class="actions" data-boba="${escapeHtml(boba)}" data-field="${field}">
          <button data-act="approve" title="Use the value in the input below">Approve</button>
          <button data-act="reject"  title="Keep catalog value, do not change">Keep catalog</button>
          <input type="${inputType}" data-role="value" value="${escapeHtml(inputVal == null ? '' : inputVal)}" />
        </div>`;
    } else {
      actionsHtml = '<span style="font-size:11px;opacity:0.4">—</span>';
    }
    return `
      <tr id="${actCellId}" data-field="${field}">
        <td class="field-name">${escapeHtml(field)}</td>
        <td><span class="val cat">${escapeHtml(catVal == null ? '∅' : catVal)}</span></td>
        <td><span class="val ocr">${escapeHtml(ocrVal == null ? '∅' : ocrVal)}</span></td>
        <td class="conf">${confDisplay}</td>
        <td><span class="status ${status}">${status}</span></td>
        <td>${actionsHtml}</td>
      </tr>`;
  }

  function wireRow(rowEl, entry, proposedFields, isReview, defaultApprove) {
    rowEl.querySelectorAll('.actions').forEach(actEl => {
      const boba = actEl.dataset.boba;
      const field = actEl.dataset.field;
      actEl.querySelector('[data-act="approve"]').addEventListener('click', () => {
        const input = actEl.querySelector('[data-role="value"]');
        setDecision(boba, field, 'approve', input.value);
        updateActionState(actEl);
      });
      actEl.querySelector('[data-act="reject"]').addEventListener('click', () => {
        setDecision(boba, field, 'reject');
        updateActionState(actEl);
      });
      actEl.querySelector('[data-role="value"]').addEventListener('input', () => {
        // If approval already set, update value live.
        const d = getDecision(boba, field);
        if (d && d.action === 'approve') {
          setDecision(boba, field, 'approve', actEl.querySelector('[data-role="value"]').value);
        }
      });
      updateActionState(actEl);
    });
    // Card-level buttons.
    const approveRowBtn = rowEl.querySelector('[data-act="approve-row"]');
    const rejectRowBtn  = rowEl.querySelector('[data-act="reject-row"]');
    const dismissBtn    = rowEl.querySelector('[data-act="dismiss"]');
    if (approveRowBtn) approveRowBtn.addEventListener('click', () => {
      proposedFields.forEach(f => {
        const actEl = rowEl.querySelector(`.actions[data-field="${f}"]`);
        if (!actEl) return;
        const input = actEl.querySelector('[data-role="value"]');
        setDecision(entry.bobaId, f, 'approve', input.value);
        updateActionState(actEl);
      });
    });
    if (rejectRowBtn) rejectRowBtn.addEventListener('click', () => {
      proposedFields.forEach(f => {
        setDecision(entry.bobaId, f, 'reject');
        const actEl = rowEl.querySelector(`.actions[data-field="${f}"]`);
        if (actEl) updateActionState(actEl);
      });
    });
    if (dismissBtn) dismissBtn.addEventListener('click', () => {
      setDecision(entry.bobaId, '__dismiss__', 'reject');
      rowEl.classList.add('dismissed');
    });
    // Initial state.
    if (getDecision(entry.bobaId, '__dismiss__')) rowEl.classList.add('dismissed');
    if (defaultApprove) {
      // Mark default-approve fields visually
      rowEl.querySelectorAll('.actions').forEach(updateActionState);
    }
    updateRowState(entry.bobaId);
    // Click image → open full size in new tab.
    rowEl.querySelector('img').addEventListener('click', e => {
      window.open(e.target.src, '_blank');
    });
  }

  function updateActionState(actEl) {
    const boba = actEl.dataset.boba;
    const field = actEl.dataset.field;
    const d = getDecision(boba, field);
    actEl.querySelector('[data-act="approve"]').classList.toggle('active', d?.action === 'approve');
    actEl.querySelector('[data-act="approve"]').classList.toggle('approve', d?.action === 'approve');
    actEl.querySelector('[data-act="reject"]').classList.toggle('active', d?.action === 'reject');
    actEl.querySelector('[data-act="reject"]').classList.toggle('reject', d?.action === 'reject');
  }

  function updateRowState(boba) {
    document.querySelectorAll(`.card-row[data-boba="${CSS.escape(boba)}"]`).forEach(row => {
      const hasApproval = Object.keys(decisions).some(k =>
        k.startsWith(boba + ':') && decisions[k]?.action === 'approve' && !k.endsWith(':__dismiss__'));
      row.classList.toggle('has-approval', hasApproval);
    });
  }

  // A row is "decided" if EVERY proposed field on it has a decision.
  // (Dismissed rows also count as decided.) Used by Hide-decided +
  // pending counters.
  function entryIsDecided(entry, kind) {
    const boba = entry.bobaId || entry.old_bobaId;
    if (getDecision(boba, '__dismiss__')) return true;
    if (kind === 'ADDITIONS') return true;  // default-approve
    const statuses = entry.statuses || {};
    const proposedFields = Object.keys(statuses).filter(f => {
      const s = statuses[f];
      return s && (s.bucket === 'UPDATE' || s.bucket === 'REVIEW');
    });
    if (!proposedFields.length) return true;
    return proposedFields.every(f => !!getDecision(boba, f));
  }
  function pendingCount(items, kind) {
    return items.filter(e => !entryIsDecided(e, kind)).length;
  }

  function updateStats() {
    const totalU = PAYLOAD.updates.length;
    const totalR = PAYLOAD.review.length;
    const totalA = PAYLOAD.additions.length;
    const pendU = pendingCount(PAYLOAD.updates, 'UPDATES');
    const pendR = pendingCount(PAYLOAD.review, 'REVIEW');
    let approvedFieldCount = 0, rejectedCount = 0;
    const approvedBobaIds = new Set();
    for (const k in decisions) {
      if (k.endsWith(':__dismiss__')) continue;
      if (decisions[k]?.action === 'approve') {
        approvedFieldCount++;
        const sep = k.lastIndexOf(':');
        if (sep > 0) approvedBobaIds.add(k.substring(0, sep));
      } else if (decisions[k]?.action === 'reject') {
        rejectedCount++;
      }
    }
    // Additions default-approve: count un-rejected ones too.
    const additionsAutoApprove = PAYLOAD.additions.filter(a => {
      const d = getDecision(a.old_bobaId, 'printedSerial');
      return !d || d.action !== 'reject';
    }).length;
    const pendingTotal = pendU + pendR;
    // Cards in modify[] = unique bobaIds across approved decisions.
    // Total field changes = approvedFieldCount. The two-pass export
    // captures every approve so the patch matches these exactly.
    $('stats').innerHTML = `
      <span class="chip" style="background:rgba(0,245,255,0.18);border-color:#00F5FF"><strong>${pendingTotal}</strong> pending · ${pendU} UPDATES · ${pendR} REVIEW</span>
      <span class="chip" style="opacity:0.7">Totals: UPDATES <strong>${totalU}</strong> · REVIEW <strong>${totalR}</strong> · ADDITIONS <strong>${totalA}</strong></span>
      <span class="chip">Approved: <strong>${approvedFieldCount}</strong> fields across <strong>${approvedBobaIds.size}</strong> cards</span>
      <span class="chip">Rejected: <strong>${rejectedCount}</strong></span>
      <span class="chip" style="background:rgba(255,77,0,0.18);border-color:#FF4D00">Patch will include: <strong>${approvedBobaIds.size} modify cards</strong> (${approvedFieldCount} fields) + <strong>${additionsAutoApprove} additions</strong></span>
    `;
  }

  // ============ FILTERS ============
  //
  // With chunked rendering, filters need to consult both rendered AND
  // unrendered items. When the user types a search query or picks a
  // field filter, we walk the full payload and render any unrendered
  // matches before applying display:none/block on the now-rendered
  // rows. Without this, a filter would silently hide matches that
  // hadn't been built yet.
  function itemMatchesFilter(item, kind, q, field, stateFilter) {
    if (q) {
      // Lightweight text-search over bobaId + catalog fields.
      const text = JSON.stringify(item).toLowerCase();
      if (!text.includes(q)) return false;
    }
    if (field) {
      if (kind === 'ADDITIONS') {
        if (field !== 'printedSerial') return false;
      } else {
        const status = item.statuses?.[field];
        if (!status) return false;
        // Only show the field's value being a candidate for decision
        // (MISMATCH for UPDATES; LOW_CONF/NULL_OCR for REVIEW).
      }
    }
    if (stateFilter) {
      const bobaId = item.bobaId || item.old_bobaId;
      const fields = kind === 'ADDITIONS' ? ['printedSerial'] :
                     Object.keys(item.statuses || {}).filter(f => f !== 'serial');
      let pending = false, approved = false, rejected = false;
      for (const f of fields) {
        const d = getDecision(bobaId, f);
        if (kind === 'UPDATES' && item.statuses[f] !== 'MISMATCH') continue;
        if (!d) pending = true;
        else if (d.action === 'approve') approved = true;
        else if (d.action === 'reject') rejected = true;
      }
      if (stateFilter === 'pending'  && !pending)  return false;
      if (stateFilter === 'approved' && !approved) return false;
      if (stateFilter === 'rejected' && !rejected) return false;
    }
    return true;
  }

  function applyFilters() {
    const q = $('search').value.toLowerCase().trim();
    const bucket = $('filter-bucket').value;
    const field = $('filter-field').value;
    const stateFilter = $('filter-status').value;
    const hideDecided = $('hide-decided')?.checked;
    const filtersActive = q || bucket !== 'all' || field || stateFilter || hideDecided;

    // If any filter is active, render every MATCHING unrendered item
    // (skip non-matches entirely so the DOM stays small even on
    // narrow filters like "field=power" against 2,475 rows). The
    // chunking observer is paused while filters are active and
    // resumes once filters clear.
    if (filtersActive) {
      ['updates', 'review', 'additions'].forEach(kind => {
        const sectionKind = kind === 'additions' ? 'ADDITIONS' :
                            kind === 'updates' ? 'UPDATES' : 'REVIEW';
        if (bucket !== 'all' && bucket !== sectionKind) return;
        const s = sectionState[kind];
        if (!s) return;
        const frag = document.createDocumentFragment();
        let scanned = s.rendered;
        // Walk unrendered tail. Only append items that match the
        // active filter; mark non-matches as 'rendered' too so we
        // don't rescan them, but skip the DOM build.
        for (let i = s.rendered; i < s.items.length; i++) {
          if (itemMatchesFilter(s.items[i], sectionKind, q, field, stateFilter)) {
            frag.appendChild(s.builder(s.items[i]));
          }
          scanned = i + 1;
        }
        if (frag.childNodes.length) {
          s.host.insertBefore(frag, s.sentinel);
        }
        s.rendered = scanned;
      });
    }

    document.querySelectorAll('.card-row').forEach(row => {
      const boba = row.dataset.boba.toLowerCase();
      const kind = row.dataset.kind;
      let visible = true;
      if (bucket !== 'all' && kind !== bucket) visible = false;
      if (visible && q) {
        const text = (boba + ' ' + (row.textContent || '').toLowerCase());
        if (!text.includes(q)) visible = false;
      }
      if (visible && field) {
        if (kind === 'ADDITIONS') {
          if (field !== 'printedSerial') visible = false;
        } else {
          const hasField = row.querySelector(`tr[data-field="${field}"]`);
          if (!hasField) visible = false;
        }
      }
      if (visible && stateFilter) {
        const proposed = row.querySelectorAll('.actions');
        let pending = false, approved = false, rejected = false;
        proposed.forEach(a => {
          const d = getDecision(a.dataset.boba, a.dataset.field);
          if (!d) pending = true;
          else if (d.action === 'approve') approved = true;
          else if (d.action === 'reject') rejected = true;
        });
        if (stateFilter === 'pending'  && !pending)  visible = false;
        if (stateFilter === 'approved' && !approved) visible = false;
        if (stateFilter === 'rejected' && !rejected) visible = false;
      }
      // Hide rows where every proposed field has a decision (or
      // dismissed). Keeps the visible list ≈ "still to review".
      if (visible && hideDecided) {
        const boba = row.dataset.boba;
        if (getDecision(boba, '__dismiss__')) {
          visible = false;
        } else {
          const proposed = row.querySelectorAll('.actions[data-field]');
          if (proposed.length) {
            const allDecided = Array.from(proposed).every(a =>
              !!getDecision(a.dataset.boba, a.dataset.field));
            if (allDecided) visible = false;
          } else if (kind === 'ADDITIONS') {
            visible = false;
          }
        }
      }
      row.style.display = visible ? '' : 'none';
    });
    // Section headers update with visible count.
    ['updates','review','additions'].forEach(s => {
      const rows = document.querySelectorAll(`#section-${s} .card-row`);
      const visibleN = Array.from(rows).filter(r => r.style.display !== 'none').length;
      const total = (sectionState[s]?.items?.length) || 0;
      const h = $('head-' + s);
      const baseText = h.textContent.split(' (')[0];
      h.textContent = filtersActive
        ? `${baseText} (${visibleN} of ${total})`
        : `${baseText} (${total})`;
    });
  }

  function applyFiltersToSection(kind) {
    // After a new chunk lands, re-evaluate which of its rows should be
    // visible per the current filter state.
    applyFilters();
  }

  // ============ BULK ACTIONS ============
  $('approve-visible-ocr').addEventListener('click', () => {
    let n = 0;
    document.querySelectorAll('.card-row').forEach(row => {
      if (row.style.display === 'none') return;
      row.querySelectorAll('.actions').forEach(actEl => {
        const input = actEl.querySelector('[data-role="value"]');
        setDecision(actEl.dataset.boba, actEl.dataset.field, 'approve', input.value);
        updateActionState(actEl);
        n++;
      });
    });
    toast(`Approved ${n} field-changes`);
  });
  $('reject-visible').addEventListener('click', () => {
    let n = 0;
    document.querySelectorAll('.card-row').forEach(row => {
      if (row.style.display === 'none') return;
      row.querySelectorAll('.actions').forEach(actEl => {
        setDecision(actEl.dataset.boba, actEl.dataset.field, 'reject');
        updateActionState(actEl);
        n++;
      });
    });
    toast(`Rejected ${n} field-changes`);
  });
  $('reset').addEventListener('click', () => {
    if (!confirm('Reset all decisions? This wipes your localStorage.')) return;
    decisions = {};
    localStorage.removeItem(LS_KEY);
    document.querySelectorAll('.card-row').forEach(r => {
      r.classList.remove('dismissed', 'has-approval');
    });
    document.querySelectorAll('.actions').forEach(updateActionState);
    updateStats();
    toast('All decisions reset');
  });

  // ============ EXPORT ============
  //
  // Two-pass build so EVERY localStorage approve decision lands in
  // the patch, not just those matching a PAYLOAD entry's statuses map.
  //
  // Why two passes: the original single-pass version walked PAYLOAD
  // entries and looked up their statuses. Decisions on bobaIds /
  // fields outside that map (cross-session leftovers, REVIEW
  // overrides on non-flagged fields, etc.) were silently dropped —
  // which is what caused the "Page reports 946 approved, patch has
  // 290 modify" mismatch Ben hit on 2026-05-25. The two-pass version
  // surfaces all approves; apply_audit_patch.py is the final
  // gatekeeper for "is this bobaId still resolvable?" via its
  // v2-fallback lookup.
  $('export').addEventListener('click', () => {
    // Index PAYLOAD entries by bobaId for fast lookup in pass 2.
    const updatesByBoba = new Map(PAYLOAD.updates.map(u => [u.bobaId, u]));
    const reviewByBoba  = new Map(PAYLOAD.review.map(r => [r.bobaId, r]));
    const addByBoba     = new Map(PAYLOAD.additions.map(a => [a.old_bobaId, a]));

    // Pass 1: walk PAYLOAD entries first so we attach full evidence
    // when we have it. Track which (boba, field) pairs landed.
    const modify = [];
    const modifyIndex = new Map();  // boba → modify entry in `modify`
    const captured = new Set();     // "boba:field" pairs already in modify

    function addChange(boba, field, value, evidence) {
      const stored = modifyIndex.get(boba);
      if (stored) {
        stored.changes[field] = value;
        if (evidence) stored.evidence[field] = evidence;
      } else {
        const entry = { old_bobaId: boba, changes: { [field]: value }, evidence: {} };
        if (evidence) entry.evidence[field] = evidence;
        modify.push(entry);
        modifyIndex.set(boba, entry);
      }
      captured.add(boba + ':' + field);
    }

    function coerce(field, raw) {
      if (field === 'power') return (raw === '' || raw == null) ? null : Number(raw);
      return raw;
    }

    for (const u of PAYLOAD.updates) {
      for (const field of Object.keys(u.statuses)) {
        const d = getDecision(u.bobaId, field);
        if (!d || d.action !== 'approve') continue;
        const ev = u.evidence?.[field] || u.ocr?.[field] || {};
        addChange(u.bobaId, field, coerce(field, d.value), ev);
      }
    }
    for (const r of PAYLOAD.review) {
      for (const field of Object.keys(r.statuses)) {
        const d = getDecision(r.bobaId, field);
        if (!d || d.action !== 'approve') continue;
        const ev = r.ocr?.[field] || {};
        addChange(r.bobaId, field, coerce(field, d.value), ev);
      }
    }

    // Pass 2: walk ALL localStorage approve decisions. Anything not
    // captured in pass 1 gets an entry too — bare evidence, but the
    // approve is real and should be in the patch. apply_audit_patch.py
    // will skip with `unknown_bobaIds` if the row no longer exists.
    //
    // printedSerial decisions are SKIPPED — those belong in additions[]
    // (default-approve + explicit-value-override below), so pulling
    // them into modify[] would duplicate the change AND bypass the
    // printedSerial → printRun integer migration in apply_audit_patch.
    const additionsBobaIdSet = new Set(PAYLOAD.additions.map(a => a.old_bobaId));
    let pass2Added = 0;
    let pass2SkippedAddition = 0;
    for (const key of Object.keys(decisions)) {
      if (key.endsWith(':__dismiss__')) continue;
      const d = decisions[key];
      if (!d || d.action !== 'approve') continue;
      if (captured.has(key)) continue;
      const sep = key.lastIndexOf(':');
      if (sep < 0) continue;
      const boba  = key.substring(0, sep);
      const field = key.substring(sep + 1);
      if (field === 'printedSerial' && additionsBobaIdSet.has(boba)) {
        pass2SkippedAddition++;
        continue;
      }
      // Reconstruct evidence from PAYLOAD lookup tables when possible.
      const src = updatesByBoba.get(boba) || reviewByBoba.get(boba);
      const ev = (src && (src.evidence?.[field] || src.ocr?.[field])) || { decision_only: true };
      addChange(boba, field, coerce(field, d.value), ev);
      pass2Added++;
    }

    // ADDITIONS — default-approve unless explicitly rejected.
    const additions = [];
    for (const a of PAYLOAD.additions) {
      const d = getDecision(a.old_bobaId, 'printedSerial');
      if (d && d.action === 'reject') continue;
      const v = (d && d.value != null && d.value !== '') ? d.value : a.additions.printedSerial;
      additions.push({
        old_bobaId: a.old_bobaId,
        additions: { printedSerial: v },
        evidence: a.evidence,
      });
    }
    // Pass 2 for additions: pick up rejected → not in payload, etc.
    // (No-op currently; left as a placeholder if we extend additions
    // to other fields.)

    const curated = {
      schema_version: 1,
      generated_at: new Date().toISOString(),
      source: 'card_audit_pipeline_curated',
      modify, additions,
    };
    const blob = new Blob([JSON.stringify(curated, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    const date = new Date().toISOString().slice(0,10);
    a.download = `curated-patch-${date}.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    const totalFields = modify.reduce((n, m) => n + Object.keys(m.changes).length, 0);
    toast(`Exported ${modify.length} cards / ${totalFields} fields (${pass2Added} cross-session; ${pass2SkippedAddition} printedSerial gated to additions) + ${additions.length} additions`);
  });

  // Wire filters.
  ['search', 'filter-bucket', 'filter-field', 'filter-status', 'hide-decided'].forEach(id => {
    const el = $(id);
    if (!el) return;
    el.addEventListener('input', applyFilters);
    el.addEventListener('change', applyFilters);
  });

  // ============ V2 → V3 bobaId localStorage migration ============
  // Decisions made against the pre-2026-05-25 (4-field) bobaId catalog
  // remain in localStorage. New HTMLs use 5-field v3 bobaIds.
  // Rekey existing decisions from v2 to v3 by looking up each entry's
  // catalog fields and computing both formulas.
  (function migrateV2ToV3() {
    function v2Id(c) {
      const hero = c.hero || c.name || '';
      const cn   = c.cardNumber || '';
      const tr   = c.treatment || '';
      const va   = c.variation || '';
      return cn + '-' + hero + '-' + tr + '-' + va;
    }
    const map = {};  // v2 → v3
    const allEntries = [...PAYLOAD.updates, ...PAYLOAD.review, ...PAYLOAD.additions];
    allEntries.forEach(e => {
      const c = e.catalog;
      if (!c) return;
      const v2 = v2Id(c);
      const v3 = e.bobaId;
      if (v2 !== v3) map[v2] = v3;
    });
    let migrated = 0;
    for (const key of Object.keys(decisions)) {
      const sep = key.lastIndexOf(':');
      if (sep < 0) continue;
      const oldBoba = key.substring(0, sep);
      const field   = key.substring(sep + 1);
      const newBoba = map[oldBoba];
      if (newBoba && newBoba !== oldBoba) {
        const newKey = newBoba + ':' + field;
        if (!(newKey in decisions)) decisions[newKey] = decisions[key];
        delete decisions[key];
        migrated++;
      }
    }
    if (migrated > 0) {
      persist();
      console.log('[review] migrated', migrated, 'v2 → v3 decisions');
    }
  })();

  // ============ INIT ============
  renderAdditions();
  renderUpdates();
  renderReview();
  updateStats();
  applyFilters();

  // ============ FLOW OPTIMIZATIONS ============
  // Keyboard shortcuts + auto-advance to next undecided row.
  // R/K = keep catalog · A/Space = approve · D = dismiss · J/↓ = next · U/↑ = prev · ? = help
  let focusedRow = null;

  function focusRow(row, scroll = true) {
    if (focusedRow === row) return;
    if (focusedRow) focusedRow.classList.remove('keyboard-focus');
    focusedRow = row;
    if (row) {
      row.classList.add('keyboard-focus');
      if (scroll) row.scrollIntoView({ block: 'center', behavior: 'smooth' });
    }
  }

  function visibleRows() {
    return Array.from(document.querySelectorAll('.card-row'))
      .filter(r => r.offsetParent !== null && !r.classList.contains('dismissed'));
  }

  function isDecided(row) {
    const boba = row.dataset.boba;
    if (!boba) return false;
    return Object.keys(decisions).some(k =>
      k.startsWith(boba + ':') && !k.endsWith(':__dismiss__') && decisions[k]?.action);
  }

  function nextRow(from, direction = 1, skipDecided = true) {
    const rows = visibleRows();
    if (!rows.length) return null;
    let idx = from ? rows.indexOf(from) : -1;
    for (let step = 1; step <= rows.length; step++) {
      const i = (idx + direction * step + rows.length) % rows.length;
      if (!skipDecided || !isDecided(rows[i])) return rows[i];
    }
    return null;
  }

  function applyToFocused(action) {
    if (!focusedRow) {
      const first = nextRow(null, 1, true) || visibleRows()[0];
      focusRow(first);
      return;
    }
    const boba = focusedRow.dataset.boba;
    const actionEls = focusedRow.querySelectorAll('.actions[data-field]');
    actionEls.forEach(actEl => {
      const field = actEl.dataset.field;
      if (action === 'approve') {
        const input = actEl.querySelector('[data-role="value"]');
        setDecision(boba, field, 'approve', input ? input.value : undefined);
      } else if (action === 'reject') {
        setDecision(boba, field, 'reject');
      } else if (action === 'dismiss') {
        setDecision(boba, '__dismiss__', 'reject');
        focusedRow.classList.add('dismissed');
      }
      updateActionState(actEl);
    });
    const next = nextRow(focusedRow, 1, true);
    if (next) focusRow(next);
  }

  document.addEventListener('keydown', e => {
    const t = e.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT')) return;
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    const k = e.key.toLowerCase();
    if (k === 'r' || k === 'k') { e.preventDefault(); applyToFocused('reject'); }
    else if (k === 'a' || k === ' ') { e.preventDefault(); applyToFocused('approve'); }
    else if (k === 'd') { e.preventDefault(); applyToFocused('dismiss'); }
    else if (k === 'j' || k === 'arrowdown') { e.preventDefault(); const n = nextRow(focusedRow, 1, false); if (n) focusRow(n); }
    else if (k === 'u' || k === 'arrowup') { e.preventDefault(); const p = nextRow(focusedRow, -1, false); if (p) focusRow(p); }
    else if (k === '?') { e.preventDefault(); toast('Keys: R/K = keep catalog · A/Space = approve · D = dismiss · J/↓ = next · U/↑ = prev'); }
  });

  document.addEventListener('click', e => {
    const row = e.target.closest('.card-row');
    if (row && !e.target.closest('button, input, select, a')) focusRow(row, false);
  });

  const focusStyle = document.createElement('style');
  focusStyle.textContent = '.card-row.keyboard-focus { outline: 3px solid #00F5FF; outline-offset: -3px; box-shadow: 0 0 24px rgba(0,245,255,0.3); }';
  document.head.appendChild(focusStyle);

  setTimeout(() => {
    const first = nextRow(null, 1, true) || visibleRows()[0];
    if (first) focusRow(first);
    toast('Keyboard shortcuts active — press ? for help');
  }, 300);
})();
</script>
</body></html>""".replace("__PAYLOAD__", payload_json.replace("</", "<\\/"))


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
    review_html = build_review_html(bundle["review"], bundle["updates"],
                                     additions=patch.get("additions"))
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
