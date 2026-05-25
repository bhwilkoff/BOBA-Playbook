#!/usr/bin/env python3
"""
apply_audit_patch.py — apply a curated patch from the card-audit
review tool to assets/data/cards.json.

Handles three operation classes:

  1. modify[] entries from the audit's reconcile step. Safe changes
     (element, power) apply unconditionally. cardNumber + name
     changes regenerate the row's bobaId; the applier first checks
     for collisions with existing rows (the catalog has known
     duplicate-cardNumber issues; we don't want to overwrite a
     legitimate row by changing another row's bobaId to match it).

  2. additions[] entries — new fields the audit captured that
     didn't exist in catalog before. Primary use: `printedSerial`
     for Inspired Ink cards.

  3. --bad-images PATH — a text file of bobaIds to nullify (set
     imageFile / imageSource / imageAvailable to null/false so the
     card re-enters the image-sourcing queue). One bobaId per line;
     blank lines + lines starting with `#` are ignored. Ben uses
     this for "wrong card art" findings during review.

Usage:
    # Dry-run (no writes) — print what would change.
    python3 pipeline/scripts/apply_audit_patch.py \\
        --catalog assets/data/cards.json \\
        --patch ~/Downloads/curated-patch-2026-05-25-2.json \\
        --bad-images ~/Desktop/bad-images.txt \\
        --dry-run

    # Apply (writes assets/data/cards.json + emits a summary).
    python3 pipeline/scripts/apply_audit_patch.py \\
        --catalog assets/data/cards.json \\
        --patch ~/Downloads/curated-patch-2026-05-25-2.json \\
        --bad-images ~/Desktop/bad-images.txt \\
        --apply

After --apply, regenerate downstream bundles via reconcile_all.py
(or whatever your normal post-catalog-edit pipeline is).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--catalog", required=True, help="Path to cards.json")
    p.add_argument("--patch", help="Curated patch JSON (modify[] + additions[])")
    p.add_argument("--bad-images",
                   help="Text file of bobaIds (one per line) whose imageFile "
                        "should be nullified")
    p.add_argument("--dry-run", action="store_true",
                   help="Don't write; print what would change.")
    p.add_argument("--apply", action="store_true",
                   help="Write the updated catalog back to --catalog.")
    return p.parse_args()


def build_boba_id(card: dict) -> str:
    """5-field bobaId — must match scripts/boba_id.py + the project
    mantra. cardNumber, hero (or name for sealed), treatment,
    variation, weapon (catalog field `element`). Trailing dashes
    intentional and stable. v3 added weapon 2026-05-25."""
    card_number = card.get("cardNumber") or ""
    hero = card.get("hero") or card.get("name") or ""
    treatment = card.get("treatment") or ""
    variation = card.get("variation") or ""
    weapon = card.get("element") or ""
    return f"{card_number}-{hero}-{treatment}-{variation}-{weapon}"


def build_boba_id_v2(card: dict) -> str:
    """OLD 4-field formula (pre-2026-05-25). Used for backwards-compat
    lookup so patches authored against the v2 catalog (notably the
    audit-review export from before the v3 migration) still apply."""
    card_number = card.get("cardNumber") or ""
    hero = card.get("hero") or card.get("name") or ""
    treatment = card.get("treatment") or ""
    variation = card.get("variation") or ""
    return f"{card_number}-{hero}-{treatment}-{variation}"


def lookup_card(target: str, by_boba_v3: dict, by_boba_v2: dict):
    """Resolve a patch entry's `old_bobaId` to a card. Tries v3 first,
    falls back to v2 (audit-review export pre-migration). Returns
    (card, ambiguity_note) — ambiguity_note is None on clean match,
    or a string explaining why we skipped (ambiguous v2 → multiple
    v3 cards). Returns (None, None) on plain miss."""
    card = by_boba_v3.get(target)
    if card is not None:
        return card, None
    # v3 miss. Try v2 fallback.
    matches = by_boba_v2.get(target)
    if not matches:
        return None, None
    if len(matches) == 1:
        return matches[0], None
    # True v2 ambiguity — the v3 migration split this v2 ID into
    # multiple cards (almost always a FIRE/GLOW weapon-variant pair).
    weapons = sorted({(c.get("element") or "<empty>") for c in matches})
    return None, f"v2-ambiguous (matches {len(matches)} v3 cards across weapons: {', '.join(weapons)})"


def apply_modifies(cards: list[dict], modifies: list[dict]) -> dict:
    """Apply modify[] entries field-by-field. Collisions on cardNumber
    or name (where the new bobaId would clash with an existing row)
    skip JUST THAT FIELD, not the whole card — safe sibling fields
    like element/power still apply. Previous behavior was to skip
    the entire card on collision, which threw away ~600 approved
    field-changes on the GLBF duplicate-row cluster."""
    by_boba = {c.get("bobaId"): c for c in cards if c.get("bobaId")}
    # v2 fallback index — same v2 ID can match multiple v3 cards
    # (FIRE/GLOW weapon variants), so list-valued.
    by_boba_v2: dict[str, list[dict]] = {}
    for c in cards:
        by_boba_v2.setdefault(build_boba_id_v2(c), []).append(c)
    cards_modified = 0
    fields_applied = 0
    field_collisions = []   # per-field skipped due to bobaId collision
    skipped_unknown = []
    skipped_ambiguous = []  # v2 IDs that match >1 v3 card
    name_cardnumber_changes = []
    for m in modifies:
        target = m.get("old_bobaId")
        changes = dict(m.get("changes") or {})
        if not target or not changes:
            continue
        card, ambig = lookup_card(target, by_boba, by_boba_v2)
        if card is None:
            if ambig:
                skipped_ambiguous.append({"old_bobaId": target, "reason": ambig})
            else:
                skipped_unknown.append(target)
            continue

        # Identify bobaId-affecting fields and decide which to drop.
        affecting = {k: v for k, v in changes.items() if k in ("cardNumber", "name")}
        if affecting:
            hypothetical = dict(card)
            hypothetical.update(affecting)
            new_bid = build_boba_id(hypothetical)
            if new_bid != target and new_bid in by_boba:
                # Drop the affecting fields so we still apply the rest.
                for k in list(affecting.keys()):
                    field_collisions.append({
                        "from_bobaId": target,
                        "field": k,
                        "proposed_value": changes[k],
                        "would_be_bobaId": new_bid,
                        "collision_with": by_boba[new_bid].get("bobaId"),
                    })
                    changes.pop(k, None)
                affecting = {}

        if not changes:
            # Every field was a collision — nothing to apply for this card.
            continue

        # Apply remaining (safe) field changes.
        for k, v in changes.items():
            card[k] = v
            fields_applied += 1

        # If the surviving changes still include name/cardNumber, regen bobaId.
        if "cardNumber" in changes or "name" in changes:
            if "name" in changes and not card.get("isSealed") and card.get("hero"):
                card["hero"] = changes["name"]
            old_bid = card.get("bobaId")
            new_bid = build_boba_id(card)
            card["bobaId"] = new_bid
            by_boba.pop(old_bid, None)
            by_boba[new_bid] = card
            name_cardnumber_changes.append({
                "from": old_bid, "to": new_bid, "changes": changes,
            })
        cards_modified += 1

    return {
        "cards_modified": cards_modified,
        "fields_applied": fields_applied,
        "skipped_unknown": skipped_unknown,
        "skipped_ambiguous": skipped_ambiguous,
        "field_collisions": field_collisions,
        "bobaid_regen_count": len(name_cardnumber_changes),
    }


def apply_additions(cards: list[dict], additions: list[dict]) -> dict:
    """Apply additions[] entries — pure field-add operations. Used by
    the audit pipeline for the new `printRun` field on Inspired Ink
    cards. Idempotent: re-running just rewrites the same value.

    NOTE on printedSerial → printRun: the audit pipeline initially
    captured the full serial string ("15/25") but Ben pointed out the
    numerator (15) is just an artifact of whichever copy was
    photographed on eBay — the per-card information is the
    DENOMINATOR (the print run: 5, 10, 25, 50). So when an
    addition says `printedSerial: "15/25"`, we strip to integer 25
    and store under `printRun`. The old `printedSerial` is also
    dropped from any card that has it (idempotent migration)."""
    import re
    by_boba = {c.get("bobaId"): c for c in cards if c.get("bobaId")}
    by_boba_v2: dict[str, list[dict]] = {}
    for c in cards:
        by_boba_v2.setdefault(build_boba_id_v2(c), []).append(c)
    applied = 0
    skipped_unknown = []
    skipped_ambiguous = []
    for a in additions:
        target = a.get("old_bobaId")
        adds = a.get("additions") or {}
        if not target or not adds:
            continue
        card, ambig = lookup_card(target, by_boba, by_boba_v2)
        if card is None:
            if ambig:
                skipped_ambiguous.append({"old_bobaId": target, "reason": ambig})
            else:
                skipped_unknown.append(target)
            continue
        for k, v in adds.items():
            # printedSerial migration: strip numerator, keep denominator.
            if k == "printedSerial":
                if isinstance(v, str) and "/" in v:
                    parts = v.split("/")
                    try:
                        denom = int(parts[-1].strip())
                        card["printRun"] = denom
                    except ValueError:
                        # Couldn't parse — store raw fallback.
                        card["printRun"] = v
                elif isinstance(v, int):
                    card["printRun"] = v
                else:
                    card["printRun"] = v
                # Migrate away from old field name on this card.
                card.pop("printedSerial", None)
            else:
                card[k] = v
        applied += 1
    return {
        "applied": applied,
        "skipped_unknown": skipped_unknown,
        "skipped_ambiguous": skipped_ambiguous,
    }


def migrate_printed_serial_to_print_run(cards: list[dict]) -> int:
    """One-shot migration: any card that already has the old
    `printedSerial` string field gets converted to integer `printRun`
    (denominator only). Called automatically by main so re-runs are
    self-healing for cards.json that may have been written with the
    old field name during earlier audit iterations."""
    import re
    migrated = 0
    for c in cards:
        if "printedSerial" not in c:
            continue
        v = c["printedSerial"]
        if isinstance(v, str) and "/" in v:
            try:
                c["printRun"] = int(v.split("/")[-1].strip())
            except ValueError:
                c["printRun"] = v
        elif isinstance(v, int):
            c["printRun"] = v
        else:
            c["printRun"] = v
        del c["printedSerial"]
        migrated += 1
    return migrated


def apply_bad_images(cards: list[dict], bobaids: list[str]) -> dict:
    """Nullify imageFile / imageSource / imageAvailable for the listed
    cards so they re-enter the sourcing queue. The image bytes on R2
    are NOT deleted here — that's a separate operation (R2 deletion
    via wrangler). The catalog change is what the apps render off of,
    so this is sufficient to remove the bad art from display."""
    by_boba = {c.get("bobaId"): c for c in cards if c.get("bobaId")}
    by_boba_v2: dict[str, list[dict]] = {}
    for c in cards:
        by_boba_v2.setdefault(build_boba_id_v2(c), []).append(c)
    applied = 0
    skipped_unknown = []
    skipped_ambiguous = []
    for bid in bobaids:
        card, ambig = lookup_card(bid, by_boba, by_boba_v2)
        if card is None:
            if ambig:
                skipped_ambiguous.append({"old_bobaId": bid, "reason": ambig})
            else:
                skipped_unknown.append(bid)
            continue
        card["imageFile"] = None
        card["imageSource"] = None
        card["imageAvailable"] = False
        applied += 1
    return {
        "applied": applied,
        "skipped_unknown": skipped_unknown,
        "skipped_ambiguous": skipped_ambiguous,
    }


def load_bad_images(path: Path) -> list[str]:
    bobaids = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # Tolerate "bobaId - human note" lines from copy-paste.
        if " - " in line:
            line = line.split(" - ", 1)[0].strip()
        bobaids.append(line)
    return bobaids


def main() -> int:
    args = parse_args()
    if not args.dry_run and not args.apply:
        print("Specify either --dry-run or --apply.", file=sys.stderr)
        return 2
    if args.dry_run and args.apply:
        print("Pick one: --dry-run OR --apply, not both.", file=sys.stderr)
        return 2

    catalog_path = Path(args.catalog)
    with open(catalog_path) as f:
        cards = json.load(f)
    print(f"[apply] catalog loaded: {len(cards)} cards", flush=True)

    # Self-healing migration: prior audit applies stored the full
    # "15/25" string under `printedSerial`. The denominator alone is
    # the per-card datum (numerator is just the photographed copy's
    # serial). Convert to integer `printRun`.
    migrated = migrate_printed_serial_to_print_run(cards)
    if migrated:
        print(f"[apply] migrated {migrated} printedSerial → printRun (integer denominator)",
              flush=True)

    summary = {"modifies": None, "additions": None, "bad_images": None}

    if args.patch:
        with open(args.patch) as f:
            patch = json.load(f)
        print(f"[apply] patch loaded: "
              f"{len(patch.get('modify', []))} modify, "
              f"{len(patch.get('additions', []))} additions",
              flush=True)
        summary["modifies"] = apply_modifies(cards, patch.get("modify", []))
        summary["additions"] = apply_additions(cards, patch.get("additions", []))

    if args.bad_images:
        bobaids = load_bad_images(Path(args.bad_images))
        print(f"[apply] bad-images list: {len(bobaids)} bobaIds",
              flush=True)
        summary["bad_images"] = apply_bad_images(cards, bobaids)

    # Report.
    print()
    if summary["modifies"]:
        m = summary["modifies"]
        n_ambig = len(m.get("skipped_ambiguous") or [])
        print(f"[modify]    cards_modified={m['cards_modified']}, "
              f"fields_applied={m['fields_applied']}, "
              f"field_collisions={len(m['field_collisions'])}, "
              f"unknown_bobaIds={len(m['skipped_unknown'])}, "
              f"v2_ambiguous={n_ambig}, "
              f"bobaId_regenerated={m['bobaid_regen_count']}")
        if m["field_collisions"]:
            print(f"\n[modify] {len(m['field_collisions'])} field-level "
                  f"collisions skipped (the target bobaId would clash with an "
                  f"existing row — that field's value stays catalog; other "
                  f"fields on the same card still applied). Sample:")
            for c in m["field_collisions"][:10]:
                print(f"  {c['from_bobaId']}")
                print(f"    {c['field']} → {c['proposed_value']!r} "
                      f"would make bobaId={c['would_be_bobaId']}")
                print(f"    collides with existing: {c['collision_with']}")
            if len(m["field_collisions"]) > 10:
                print(f"  … and {len(m['field_collisions']) - 10} more")
        if m["skipped_unknown"]:
            print(f"\n[modify] UNKNOWN bobaIds (catalog doesn't have these):")
            for bid in m["skipped_unknown"][:10]:
                print(f"  {bid}")
            if len(m["skipped_unknown"]) > 10:
                print(f"  … and {len(m['skipped_unknown']) - 10} more")
        if m.get("skipped_ambiguous"):
            print(f"\n[modify] V2-AMBIGUOUS bobaIds (the pre-2026-05-25 4-field ID "
                  f"matches multiple v3 cards — usually a FIRE/GLOW weapon-variant "
                  f"pair the patch couldn't disambiguate). Re-export from review.html "
                  f"to pick up v3-keyed IDs, OR add the weapon suffix manually:")
            for entry in m["skipped_ambiguous"][:10]:
                print(f"  {entry['old_bobaId']}  →  {entry['reason']}")
            if len(m["skipped_ambiguous"]) > 10:
                print(f"  … and {len(m['skipped_ambiguous']) - 10} more")
    if summary["additions"]:
        a = summary["additions"]
        n_ambig = len(a.get("skipped_ambiguous") or [])
        print(f"\n[additions] applied={a['applied']}, "
              f"unknown_bobaIds={len(a['skipped_unknown'])}, "
              f"v2_ambiguous={n_ambig}")
    if summary["bad_images"]:
        b = summary["bad_images"]
        n_ambig = len(b.get("skipped_ambiguous") or [])
        print(f"\n[bad_images] nullified={b['applied']}, "
              f"unknown_bobaIds={len(b['skipped_unknown'])}, "
              f"v2_ambiguous={n_ambig}")
        if b["skipped_unknown"]:
            print(f"  Unknown:")
            for bid in b["skipped_unknown"]:
                print(f"    {bid}")
        if b.get("skipped_ambiguous"):
            print(f"  V2-ambiguous (need weapon suffix):")
            for entry in b["skipped_ambiguous"]:
                print(f"    {entry['old_bobaId']} → {entry['reason']}")

    if args.dry_run:
        print(f"\n[apply] DRY RUN — no writes.")
        return 0

    if args.apply:
        # Write the updated catalog atomically (temp file + rename).
        tmp = catalog_path.with_suffix(catalog_path.suffix + ".tmp")
        tmp.write_text(json.dumps(cards, indent=2))
        tmp.replace(catalog_path)
        print(f"\n[apply] WROTE {catalog_path}")
        print(f"\nNext step: regenerate downstream bundles "
              f"(BOBAPlaybook/display-cards.json, etc.) via your normal "
              f"post-catalog-edit pipeline (typically reconcile_all.py).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
