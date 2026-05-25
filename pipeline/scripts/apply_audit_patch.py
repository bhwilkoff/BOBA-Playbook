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
    """4-field bobaId — must match scripts/boba_id.py + the project
    mantra. cardNumber, hero (or name for sealed), treatment,
    variation. Trailing dashes intentional and stable."""
    card_number = card.get("cardNumber") or ""
    hero = card.get("hero") or card.get("name") or ""
    treatment = card.get("treatment") or ""
    variation = card.get("variation") or ""
    return f"{card_number}-{hero}-{treatment}-{variation}"


def apply_modifies(cards: list[dict], modifies: list[dict]) -> dict:
    """Apply modify[] entries. Returns a summary dict with counts +
    a list of collisions for cardNumber/name changes."""
    by_boba = {c.get("bobaId"): c for c in cards if c.get("bobaId")}
    applied = 0
    collisions = []
    skipped_unknown = []
    name_cardnumber_changes = []
    for m in modifies:
        target = m.get("old_bobaId")
        changes = m.get("changes") or {}
        if not target or not changes:
            continue
        card = by_boba.get(target)
        if card is None:
            skipped_unknown.append(target)
            continue
        # cardNumber / name changes regenerate bobaId — check for
        # collisions first. If the new bobaId already exists as a
        # different row, refuse to apply.
        if "cardNumber" in changes or "name" in changes:
            hypothetical = dict(card)
            hypothetical.update(changes)
            new_bid = build_boba_id(hypothetical)
            if new_bid != target and new_bid in by_boba:
                collisions.append({
                    "from_bobaId": target,
                    "to_bobaId": new_bid,
                    "changes": changes,
                    "collision_with": by_boba[new_bid].get("bobaId"),
                })
                continue
            name_cardnumber_changes.append({
                "from": target, "to": new_bid, "changes": changes,
            })
        # Apply the change.
        for k, v in changes.items():
            card[k] = v
        # Regen bobaId + hero/name link if needed.
        if "cardNumber" in changes or "name" in changes:
            # If name changed, hero should follow for non-sealed cards.
            if "name" in changes and not card.get("isSealed") and card.get("hero"):
                card["hero"] = changes["name"]
            old_bid = card.get("bobaId")
            new_bid = build_boba_id(card)
            card["bobaId"] = new_bid
            # Re-key the map so further modifies in this batch find it.
            by_boba.pop(old_bid, None)
            by_boba[new_bid] = card
        applied += 1
    return {
        "applied": applied,
        "skipped_unknown": skipped_unknown,
        "collisions": collisions,
        "bobaid_regen_count": len(name_cardnumber_changes),
    }


def apply_additions(cards: list[dict], additions: list[dict]) -> dict:
    """Apply additions[] entries — pure field-add operations. Used by
    the audit pipeline for the new `printedSerial` field on Inspired
    Ink cards. Idempotent: re-running just rewrites the same value."""
    by_boba = {c.get("bobaId"): c for c in cards if c.get("bobaId")}
    applied = 0
    skipped_unknown = []
    for a in additions:
        target = a.get("old_bobaId")
        adds = a.get("additions") or {}
        if not target or not adds:
            continue
        card = by_boba.get(target)
        if card is None:
            skipped_unknown.append(target)
            continue
        for k, v in adds.items():
            card[k] = v
        applied += 1
    return {"applied": applied, "skipped_unknown": skipped_unknown}


def apply_bad_images(cards: list[dict], bobaids: list[str]) -> dict:
    """Nullify imageFile / imageSource / imageAvailable for the listed
    cards so they re-enter the sourcing queue. The image bytes on R2
    are NOT deleted here — that's a separate operation (R2 deletion
    via wrangler). The catalog change is what the apps render off of,
    so this is sufficient to remove the bad art from display."""
    by_boba = {c.get("bobaId"): c for c in cards if c.get("bobaId")}
    applied = 0
    skipped_unknown = []
    for bid in bobaids:
        card = by_boba.get(bid)
        if card is None:
            skipped_unknown.append(bid)
            continue
        card["imageFile"] = None
        card["imageSource"] = None
        card["imageAvailable"] = False
        applied += 1
    return {"applied": applied, "skipped_unknown": skipped_unknown}


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
        print(f"[modify]    applied={m['applied']}, "
              f"collisions={len(m['collisions'])}, "
              f"unknown_bobaIds={len(m['skipped_unknown'])}, "
              f"bobaId_regenerated={m['bobaid_regen_count']}")
        if m["collisions"]:
            print(f"\n[modify] COLLISIONS — these were SKIPPED. The target "
                  f"bobaId already exists as a different row in catalog. "
                  f"Manual review needed:")
            for c in m["collisions"][:20]:
                print(f"  {c['from_bobaId']}")
                print(f"    proposed change: {c['changes']}")
                print(f"    new bobaId would be: {c['to_bobaId']}")
                print(f"    collides with existing: {c['collision_with']}")
            if len(m["collisions"]) > 20:
                print(f"  … and {len(m['collisions']) - 20} more")
        if m["skipped_unknown"]:
            print(f"\n[modify] UNKNOWN bobaIds (catalog doesn't have these):")
            for bid in m["skipped_unknown"][:10]:
                print(f"  {bid}")
            if len(m["skipped_unknown"]) > 10:
                print(f"  … and {len(m['skipped_unknown']) - 10} more")
    if summary["additions"]:
        a = summary["additions"]
        print(f"\n[additions] applied={a['applied']}, "
              f"unknown_bobaIds={len(a['skipped_unknown'])}")
    if summary["bad_images"]:
        b = summary["bad_images"]
        print(f"\n[bad_images] nullified={b['applied']}, "
              f"unknown_bobaIds={len(b['skipped_unknown'])}")
        if b["skipped_unknown"]:
            print(f"  Unknown:")
            for bid in b["skipped_unknown"]:
                print(f"    {bid}")

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
