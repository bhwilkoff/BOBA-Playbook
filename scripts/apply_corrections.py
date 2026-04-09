#!/usr/bin/env python3
"""
apply_corrections.py

Two jobs in one pass:

  1. FIELD CORRECTIONS — fetches approved rows from card_corrections and
     applies them to unified-cards/data/cards.json (the master catalog).

  2. MISSING ART CHECK — fetches pending rows from card_image_overrides and
     cross-references them against cards.json.  Any card that now has an
     imageFile gets auto-resolved in Supabase (status → 'resolved') so the
     app unhides it.  Cards still missing art are listed so you know what
     still needs to be found from cowork.

After running, re-run your sync pipeline to regenerate display-cards.json,
cards-head.json, and assets/data/cards.json, then commit and push.

Environment variables required:
  SUPABASE_SERVICE_KEY  — service-role key (bypasses RLS; never the anon key)
                          Supabase dashboard → Project Settings → API → service_role

Optional:
  SUPABASE_URL          — defaults to the project URL already in Config.swift

Usage:
  python3 scripts/apply_corrections.py
  python3 scripts/apply_corrections.py --dry-run
  python3 scripts/apply_corrections.py --mark-applied
  python3 scripts/apply_corrections.py --cards-json /path/to/cards.json

Flags:
  --dry-run        Show what would change without writing anything to disk or
                   Supabase
  --mark-applied   Stamp processed field corrections as status='applied' so
                   they are excluded from future runs
  --cards-json     Explicit path to master cards.json (auto-detected if omitted)
"""

import json
import os
import sys
import argparse
import urllib.request
import urllib.error
from pathlib import Path

# ── Supabase project defaults ─────────────────────────────────────────────────
DEFAULT_SUPABASE_URL = "https://pazkimtkwwwekuguxkff.supabase.co"

# ── Field mapping: correction key (snake_case) → cards.json key (camelCase) ──
FIELD_MAP = {
    "hero":         "hero",
    "element":      "element",
    "set":          "set",
    "variation":    "variation",
    "treatment":    "treatment",
    "play_ability": "playAbility",
}

UPPERCASE_FIELDS = {"element"}

# ── Canonical bobaId ──────────────────────────────────────────────────────────
# Mantra: **One Image per Card. One ID per Card.**
# The formula is defined in scripts/boba_id.py (shared with the Cowork-side
# research repo). Imported here so both sides can never drift.
_THIS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(_THIS_DIR))
try:
    from boba_id import boba_id, build_boba_index  # type: ignore
except ImportError:
    # Inline fallback — keep EXACT formula in sync with scripts/boba_id.py
    def boba_id(card: dict) -> str:
        cn    = str(card.get("cardNumber") or "").strip()
        hero  = str(card.get("hero") or card.get("name") or "").strip()
        treat = str(card.get("treatment") or "").strip()
        var   = str(card.get("variation") or "").strip()
        return f"{cn}-{hero}-{treat}-{var}"

    def build_boba_index(cards):
        idx, dupes = {}, []
        for i, c in enumerate(cards):
            bid = boba_id(c)
            if bid in idx:
                dupes.append(bid)
            else:
                idx[bid] = (i, c)
        if dupes:
            print(f"⚠ {len(dupes)} duplicate bobaId(s) in catalog — first wins.")
        return idx

CARDS_JSON_CANDIDATES = [
    # Primary (canonical master catalog maintained by Cowork)
    Path.home() / "Documents/Claude/Projects/Bo Jackson Battle Arena Research/unified-cards/data/cards.json",
    Path.home() / "Documents/Bo Jackson Battle Arena Research/unified-cards/data/cards.json",
    # Fallback (downstream bundle shipped with the web app)
    Path(__file__).resolve().parent.parent / "assets" / "data" / "cards.json",
]


# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Apply approved Supabase corrections to master cards.json and reconcile missing art"
    )
    parser.add_argument("--dry-run", action="store_true",
                        help="Preview changes without writing anything")
    parser.add_argument("--mark-applied", action="store_true",
                        help="Stamp processed field corrections as status='applied' in Supabase")
    parser.add_argument("--cards-json", default=None,
                        help="Explicit path to master cards.json")
    args = parser.parse_args()

    # ── Credentials ──────────────────────────────────────────────────────────
    supabase_url = os.environ.get("SUPABASE_URL", DEFAULT_SUPABASE_URL)
    service_key  = os.environ.get("SUPABASE_SERVICE_KEY", "").strip()

    if not service_key:
        print("ERROR: SUPABASE_SERVICE_KEY is not set.")
        print()
        print("  Get it from: Supabase dashboard → Project Settings → API")
        print("  Then run:    export SUPABASE_SERVICE_KEY='eyJ...'")
        sys.exit(1)

    # ── Locate cards.json ─────────────────────────────────────────────────────
    if args.cards_json:
        cards_path = Path(args.cards_json)
        if not cards_path.exists():
            print(f"ERROR: --cards-json path not found: {cards_path}")
            sys.exit(1)
    else:
        cards_path = next((p for p in CARDS_JSON_CANDIDATES if p.exists()), None)
        if not cards_path:
            print("ERROR: Could not auto-detect cards.json.")
            print("  Use --cards-json /path/to/unified-cards/data/cards.json")
            sys.exit(1)

    print(f"Source:  {cards_path}")
    print(f"Project: {supabase_url}")
    if args.dry_run:
        print("Mode:    DRY RUN — nothing will be written or updated in Supabase")
    print()

    # ── Load cards.json once — both jobs use it ───────────────────────────────
    with open(cards_path, encoding="utf-8") as f:
        cards = json.load(f)
    print(f"Loaded {len(cards):,} cards from JSON.")
    print()

    # Build lookup: cardNumber → [(index, card), ...]
    index: dict[str, list[tuple[int, dict]]] = {}
    for i, card in enumerate(cards):
        cn = str(card.get("cardNumber", "")).strip()
        index.setdefault(cn, []).append((i, card))

    # Build lookup: bobaId → (index, card) — the canonical unique identifier.
    # Mantra: One Image per Card. One ID per Card.
    boba_index = build_boba_index(cards)
    if len(boba_index) != len(cards):
        print(f"⚠ cards.json has {len(cards) - len(boba_index)} bobaId collision(s) "
              "— data bug, investigate before trusting corrections.")
        print()

    cards_modified = False

    # ═════════════════════════════════════════════════════════════════════════
    # JOB 1 — FIELD CORRECTIONS
    # ═════════════════════════════════════════════════════════════════════════
    print("=" * 60)
    print("JOB 1 — FIELD CORRECTIONS")
    print("=" * 60)

    corrections = fetch_json(
        supabase_url, service_key,
        "/rest/v1/card_corrections"
        "?status=eq.approved"
        "&select=id,card_number,boba_id,corrections,notes,card_hero,card_element,card_power,card_treatment"
        "&order=created_at.asc"
    )

    if not corrections:
        print("No approved corrections found.\n")
    else:
        print(f"Found {len(corrections)} approved correction(s).\n")
        applied_ids, change_log, skipped = apply_field_corrections(
            corrections, cards, index, boba_index, args.dry_run
        )
        print_corrections_report(change_log, skipped, args.dry_run)

        if not args.dry_run and change_log and any(e["effective"] for e in change_log):
            cards_modified = True
            if args.mark_applied and applied_ids:
                patch_supabase(
                    supabase_url, service_key,
                    f"/rest/v1/card_corrections?id=in.({','.join(str(i) for i in applied_ids)})",
                    {"status": "applied"},
                    f"✓ Marked {len(applied_ids)} correction(s) as 'applied' in Supabase."
                )
            elif not args.mark_applied:
                print("Tip: re-run with --mark-applied to exclude these from future runs.\n")

    # ═════════════════════════════════════════════════════════════════════════
    # JOB 2 — MISSING ART RECONCILIATION
    # ═════════════════════════════════════════════════════════════════════════
    print("=" * 60)
    print("JOB 2 — MISSING ART RECONCILIATION")
    print("=" * 60)

    overrides = fetch_json(
        supabase_url, service_key,
        "/rest/v1/card_image_overrides"
        "?status=eq.pending"
        "&select=id,card_number,boba_id,action"
        "&order=created_at.asc"
    )

    if not overrides:
        print("No pending image overrides — missing art queue is clear.\n")
    else:
        print(f"Found {len(overrides)} card(s) in the missing art queue.\n")
        resolve_ids   = []  # overrides where art has been restored in cards.json
        still_missing = []  # overrides where art is still absent

        for ov in overrides:
            card_num = str(ov.get("card_number", "")).strip()
            ov_bid   = (ov.get("boba_id") or "").strip()

            # Prefer boba_id — exact single card. Fall back to cardNumber sweep
            # (legacy behavior: treat ANY matching-cardNumber card with art as
            # "restored", since older overrides don't carry hero/treatment).
            if ov_bid:
                match = boba_index.get(ov_bid)
                if match:
                    _, card = match
                    has_art = bool(card.get("imageFile"))
                    hero    = card.get("hero", "?")
                else:
                    has_art = False
                    hero    = "? (boba_id not found)"
                label = ov_bid
            else:
                matches = index.get(card_num, [])
                has_art = any(bool(c.get("imageFile")) for _, c in matches)
                hero    = matches[0][1].get("hero", "?") if matches else "?"
                label   = card_num

            if has_art:
                resolve_ids.append(ov["id"])
            else:
                still_missing.append((label, hero))

        if resolve_ids:
            verb = "Would resolve" if args.dry_run else "Resolved"
            print(f"  {verb} {len(resolve_ids)} override(s) — art is back in cards.json:")
            for ov in overrides:
                if ov["id"] in resolve_ids:
                    label = (ov.get("boba_id") or ov.get("card_number") or "?").strip()
                    print(f"    {label}")
            print()
            if not args.dry_run:
                patch_supabase(
                    supabase_url, service_key,
                    f"/rest/v1/card_image_overrides?id=in.({','.join(str(i) for i in resolve_ids)})",
                    {"status": "resolved"},
                    f"  ✓ Marked {len(resolve_ids)} override(s) as 'resolved' in Supabase."
                )
                print("  The app will stop hiding these images on next sign-in.\n")

        if still_missing:
            print(f"  Still missing art for {len(still_missing)} card(s):")
            for label, hero in still_missing:
                print(f"    {label}  [{hero}]")
            print()
            print("  To restore: add the image to unified-cards/images/, re-run")
            print("  your sync pipeline, then run this script again.\n")
        else:
            print("  All previously removed images now have art. Queue clear.\n")

    # ── Write cards.json if either job modified it ────────────────────────────
    if args.dry_run:
        print("─" * 60)
        print("Dry run complete — nothing written.")
        return

    if cards_modified:
        with open(cards_path, "w", encoding="utf-8") as f:
            json.dump(cards, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print("─" * 60)
        print(f"✓ Written: {cards_path}")
        print()
        print("Next steps:")
        print("  1. Re-run your sync pipeline to regenerate:")
        print("       BOBAPlaybook/display-cards.json")
        print("       BOBAPlaybook/cards-head.json")
        print("       assets/data/cards.json")
        print("       assets/data/search-index.json")
        print("       assets/data/categories.json")
        print("  2. Commit and push to deploy.")
    else:
        print("─" * 60)
        print("No changes to write to cards.json.")


# ─────────────────────────────────────────────────────────────────────────────
# Field corrections helpers
# ─────────────────────────────────────────────────────────────────────────────

def apply_field_corrections(corrections, cards, index, boba_index, dry_run):
    applied_ids = []
    skipped     = []
    change_log  = []

    for corr in corrections:
        corr_id   = corr["id"]
        card_num  = str(corr.get("card_number", "")).strip()
        corr_bid  = (corr.get("boba_id") or "").strip()
        fields    = corr.get("corrections") or {}
        notes     = (corr.get("notes") or "").strip()
        ctx_hero  = (corr.get("card_hero") or "").strip()
        ctx_treat = (corr.get("card_treatment") or "").strip()

        if not fields:
            skipped.append((corr_id, card_num or corr_bid or "?", "No fields to apply"))
            continue

        # ── PRIMARY LOOKUP: boba_id ────────────────────────────────────────────
        # If the correction row carries a boba_id, it is authoritative — one
        # exact match or nothing. This short-circuits all legacy disambiguation.
        idx = card = None
        if corr_bid:
            match = boba_index.get(corr_bid)
            if not match:
                skipped.append((corr_id, corr_bid, "boba_id not found in JSON"))
                continue
            idx, card = match
        else:
            # ── FALLBACK: legacy card_number + hero + treatment disambiguation
            if not card_num:
                skipped.append((corr_id, "?", "Missing card_number (and no boba_id)"))
                continue

            matches = index.get(card_num, [])
            if not matches:
                skipped.append((corr_id, card_num, "card_number not found in JSON"))
                continue

            if len(matches) > 1:
                if ctx_hero:
                    hero_m = [(i, c) for i, c in matches if c.get("hero", "") == ctx_hero]
                    if len(hero_m) == 1:
                        matches = hero_m
                    elif len(hero_m) > 1 and ctx_treat:
                        treat_m = [(i, c) for i, c in hero_m
                                   if (c.get("treatment") or "") == ctx_treat]
                        if len(treat_m) == 1:
                            matches = treat_m

            if len(matches) > 1:
                heroes = ", ".join(
                    f"{c.get('hero','?')} ({c.get('treatment','?')})" for _, c in matches
                )
                skipped.append((corr_id, card_num,
                    f"Ambiguous — {len(matches)} cards share this number ({heroes}). "
                    f"Fix by populating boba_id on the correction row."))
                continue

            idx, card = matches[0]
        card_changes = []
        any_effective = False

        for corr_key, new_val in fields.items():
            json_key = FIELD_MAP.get(corr_key)
            if not json_key:
                card_changes.append(f"  [unknown field '{corr_key}' — skipped]")
                continue
            if isinstance(new_val, str):
                new_val = new_val.strip()
            if corr_key in UPPERCASE_FIELDS and isinstance(new_val, str):
                new_val = new_val.upper()
            if new_val == "":
                new_val = None

            old_val = card.get(json_key)
            if old_val == new_val:
                card_changes.append(f"  {json_key}: unchanged (already {_fmt(new_val)})")
                continue

            if not dry_run:
                cards[idx][json_key] = new_val
            card_changes.append(f"  {json_key}: {_fmt(old_val)} → {_fmt(new_val)}")
            any_effective = True

        entry = {
            "id":          corr_id,
            "card_number": card_num,
            "hero":        card.get("hero", ""),
            "treatment":   card.get("treatment", ""),
            "notes":       notes,
            "changes":     card_changes,
            "effective":   any_effective,
        }
        change_log.append(entry)
        if any_effective:
            applied_ids.append(corr_id)
        else:
            skipped.append((corr_id, card_num, "All fields already at corrected values"))

    return applied_ids, change_log, skipped


def print_corrections_report(change_log, skipped, dry_run):
    effective = [e for e in change_log if e["effective"]]
    noop      = [e for e in change_log if not e["effective"]]

    if effective:
        verb = "Would apply" if dry_run else "Applied"
        print(f"{verb} {len(effective)} correction(s):\n")
        for e in effective:
            parts = [e["hero"], e.get("treatment", "")]
            tag   = "  [" + " · ".join(p for p in parts if p) + "]" if any(parts) else ""
            print(f"  #{e['id']}  {e['card_number']}{tag}")
            if e["notes"]:
                print(f"  Notes: {e['notes']}")
            for line in e["changes"]:
                print(line)
            print()

    if skipped or noop:
        print(f"Skipped {len(skipped) + len(noop)} correction(s):\n")
        for (cid, cn, reason) in skipped:
            print(f"  #{cid}  {cn}: {reason}")
        for e in noop:
            print(f"  #{e['id']}  {e['card_number']}: no effective changes")
        print()


# ─────────────────────────────────────────────────────────────────────────────
# Supabase helpers
# ─────────────────────────────────────────────────────────────────────────────

def fetch_json(supabase_url: str, service_key: str, path: str) -> list[dict]:
    url = supabase_url + path
    req = urllib.request.Request(url, headers={
        "apikey":        service_key,
        "Authorization": f"Bearer {service_key}",
        "Accept":        "application/json",
    })
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"ERROR fetching {path}: HTTP {e.code} {e.reason}")
        print(e.read().decode(errors="replace"))
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"ERROR: Could not reach Supabase: {e.reason}")
        sys.exit(1)


def patch_supabase(supabase_url: str, service_key: str, path: str,
                   payload: dict, success_msg: str) -> None:
    url  = supabase_url + path
    body = json.dumps(payload).encode()
    req  = urllib.request.Request(url, data=body, method="PATCH", headers={
        "apikey":        service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type":  "application/json",
        "Prefer":        "return=minimal",
    })
    try:
        with urllib.request.urlopen(req) as _:
            print(success_msg)
    except urllib.error.HTTPError as e:
        print(f"WARNING: PATCH failed: HTTP {e.code}")
        print(e.read().decode(errors="replace"))


def _fmt(val) -> str:
    return "null" if val is None else f"'{val}'"


if __name__ == "__main__":
    main()
