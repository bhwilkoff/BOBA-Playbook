#!/usr/bin/env python3
"""
import_new_cards.py — One-off importer for beta-tester-supplied cards.

Adds the 6 "First Reward Promo" + "Top 8" cards identified in
~/Downloads/BoBA Playbook Singles v2.xlsx — the spreadsheet's Skeee
RPU-1 row is intentionally skipped because the catalog already
contains it.

For each new card:
  • Compute bobaId via scripts/boba_id.py (4-field formula).
  • Verify the bobaId is NOT already in cards.json (defends against
    accidental re-import).
  • If a PNG is provided, generate WebP tiers per DECISIONS.md #008
    (full ≤1200px Q75, thumb 200px Q60), HEAD-check the R2 keys to
    refuse-to-overwrite per DECISIONS.md #026, then PUT to R2.
  • If no PNG is provided, ship the card record with imageFile=null /
    imageAvailable=false so the existing Stage A→B→C pipeline can
    pick the art up later.
  • Patch all 5 catalog bundles in lockstep (cards.json,
    cards-slim.json, cards-head.json [assets], display-cards.json,
    cards-head.json [iOS bundle]).

USAGE
─────
    python scripts/import_new_cards.py             # dry-run, no writes
    python scripts/import_new_cards.py --apply     # writes R2 + bundles

ENV (required for --apply when uploading images):
    R2_ACCOUNT_ID, R2_ACCESS_KEY, R2_SECRET_KEY, R2_BUCKET

Run from repo root.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import boto3
from botocore.config import Config
from dotenv import load_dotenv
from PIL import Image

# Make the sibling boba_id module importable.
REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))
from boba_id import boba_id  # noqa: E402

load_dotenv(REPO / ".env")

# Catalog bundle locations (same five bundles Stage C patches).
BUNDLES: list[Path] = [
    REPO / "assets" / "data" / "cards.json",
    REPO / "assets" / "data" / "cards-slim.json",
    REPO / "assets" / "data" / "cards-head.json",
    REPO / "BOBAPlaybook" / "display-cards.json",
    REPO / "BOBAPlaybook" / "cards-head.json",
]

# WebP tier specs per DECISIONS.md #008.
FULL_MAX_DIM   = 1200
FULL_QUALITY   = 75
THUMB_MAX_DIM  = 200
THUMB_QUALITY  = 60

# Source PNGs the user provided. None when there is no source yet —
# the entry is added with imageAvailable=false and the auto-pipeline
# will fill in later.
NEW_CARDS_DIR = Path("/Users/bhwilkoff/Downloads/New Cards")


@dataclass
class NewCardSpec:
    cardNumber: str
    name: str
    hero: str
    cardType: str            # "Hero" / "Play" / "HotDog" / "Sealed Product"
    set: str
    subSet: str
    variation: str           # may be ""
    treatment: str           # may be ""
    release: str
    element: str             # uppercase per catalog convention
    power: Optional[int]
    playCost: Optional[int]
    playAbility: Optional[str]
    athleteInspiration: Optional[str]
    isInspiredInk: bool
    rookieInspired: bool
    isBonusPlay: bool
    isHTD: bool
    dbs: Optional[int]
    dbsTier: Optional[str]
    source_png: Optional[Path]  # absolute path or None


# Canonical specs for the six new entries. Field choices follow the
# existing catalog conventions cross-referenced against the
# spreadsheet (Promo set/release matches the Skeee RPU-1 precedent).
SPECS: list[NewCardSpec] = [
    NewCardSpec(
        cardNumber="Promo", name="A.I.", hero="A.I.", cardType="Hero",
        set="Promo Cards", subSet="First Reward Promo",
        variation="", treatment="Exclusive Battlefoil",
        release="Promo", element="GLOW",
        power=195, playCost=0, playAbility=None,
        athleteInspiration="Allen Iverson",
        isInspiredInk=False, rookieInspired=False,
        isBonusPlay=False, isHTD=False, dbs=None, dbsTier=None,
        source_png=NEW_CARDS_DIR / "IMG_8512.png",
    ),
    NewCardSpec(
        cardNumber="Promo", name="Amon-Ra", hero="Amon-Ra", cardType="Hero",
        set="Promo Cards", subSet="First Reward Promo",
        variation="", treatment="Exclusive Battlefoil",
        release="Promo", element="GLOW",
        power=195, playCost=0, playAbility=None,
        athleteInspiration="Amon-Ra St. Brown",
        isInspiredInk=False, rookieInspired=False,
        isBonusPlay=False, isHTD=False, dbs=None, dbsTier=None,
        source_png=NEW_CARDS_DIR / "IMG_8509.png",
    ),
    NewCardSpec(
        cardNumber="Promo", name="Bojax", hero="Bojax", cardType="Hero",
        set="Promo Cards", subSet="First Reward Promo",
        variation="", treatment="Exclusive Battlefoil",
        release="Promo", element="GLOW",
        power=195, playCost=0, playAbility=None,
        athleteInspiration="Bo Jackson",
        isInspiredInk=False, rookieInspired=False,
        isBonusPlay=False, isHTD=False, dbs=None, dbsTier=None,
        source_png=NEW_CARDS_DIR / "IMG_8511.png",
    ),
    NewCardSpec(
        cardNumber="Promo", name="Brandi", hero="Brandi", cardType="Hero",
        set="Promo Cards", subSet="First Reward Promo",
        variation="", treatment="Exclusive Battlefoil",
        release="Promo", element="GLOW",
        power=195, playCost=0, playAbility=None,
        athleteInspiration="Brandi Chastain",
        isInspiredInk=False, rookieInspired=False,
        isBonusPlay=False, isHTD=False, dbs=None, dbsTier=None,
        source_png=None,  # no image provided yet — pipeline can fill in
    ),
    NewCardSpec(
        cardNumber="Promo", name="Cruschman", hero="Cruschman", cardType="Hero",
        set="Promo Cards", subSet="First Reward Promo",
        variation="", treatment="Exclusive Battlefoil",
        release="Promo", element="GLOW",
        power=195, playCost=0, playAbility=None,
        athleteInspiration="Adley Rutschman",
        isInspiredInk=False, rookieInspired=False,
        isBonusPlay=False, isHTD=False, dbs=None, dbsTier=None,
        source_png=NEW_CARDS_DIR / "IMG_8510.png",
    ),
    NewCardSpec(
        cardNumber="Top 8", name="Bojax", hero="Bojax", cardType="Hero",
        set="Promo Cards", subSet="2025 Apex",
        variation="2025 World Championships Top 8",
        treatment="Alt Art Battlefoil",
        release="Promo", element="ALT",
        power=200, playCost=0, playAbility=None,
        athleteInspiration="Bo Jackson",
        isInspiredInk=False, rookieInspired=False,
        isBonusPlay=False, isHTD=False, dbs=None, dbsTier=None,
        source_png=None,  # no image provided yet
    ),
]


def make_r2_client():
    account_id  = os.environ["R2_ACCOUNT_ID"]
    access_key  = os.environ["R2_ACCESS_KEY"]
    secret_key  = os.environ["R2_SECRET_KEY"]
    return boto3.client(
        "s3",
        endpoint_url=f"https://{account_id}.r2.cloudflarestorage.com",
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(signature_version="s3v4", retries={"max_attempts": 3}),
    )


def safe_filename_for_boba_id(bid: str) -> str:
    """Match the convention used by stage_c_commit.safe_filename_for_boba_id."""
    out = []
    for ch in bid:
        if ch.isalnum() or ch in ("-", "_", "."):
            out.append(ch)
        else:
            out.append("_")
    return "".join(out).rstrip("_-") + ".webp"


def generate_tiers(png_path: Path) -> tuple[bytes, bytes]:
    src = Image.open(png_path).convert("RGB")
    def resize(img: Image.Image, max_dim: int) -> Image.Image:
        w, h = img.size
        if max(w, h) <= max_dim:
            return img
        if w >= h:
            return img.resize((max_dim, int(h * (max_dim / w))), Image.LANCZOS)
        return img.resize((int(w * (max_dim / h)), max_dim), Image.LANCZOS)
    full_buf  = io.BytesIO(); resize(src, FULL_MAX_DIM ).save(full_buf,  format="WEBP", quality=FULL_QUALITY)
    thumb_buf = io.BytesIO(); resize(src, THUMB_MAX_DIM).save(thumb_buf, format="WEBP", quality=THUMB_QUALITY)
    return full_buf.getvalue(), thumb_buf.getvalue()


def upload_with_guard(r2, bucket: str, key: str, body: bytes) -> str:
    """HEAD-check before PUT — refuse to overwrite per DECISIONS.md #026 / #008.

    Returns "ok" on success, "exists" if the key already had bytes (we
    DO NOT overwrite — R2 has no version history)."""
    try:
        r2.head_object(Bucket=bucket, Key=key)
        return "exists"
    except r2.exceptions.ClientError as e:
        code = e.response.get("Error", {}).get("Code", "")
        if code not in ("404", "NoSuchKey", "NotFound"):
            raise
    r2.put_object(
        Bucket=bucket, Key=key, Body=body,
        ContentType="image/webp",
        CacheControl="public, max-age=31536000, immutable",
    )
    return "ok"


def build_card_record(spec: NewCardSpec, image_filename: Optional[str]) -> dict:
    """Build the JSON record for a new card, matching the existing
    cards.json field shape exactly. bobaId is computed BEFORE the
    record is finalized; imageFile + imageAvailable reflect whether
    we uploaded an image."""
    record = {
        "cardNumber":         spec.cardNumber,
        "name":               spec.name,
        "hero":               spec.hero,
        "cardType":           spec.cardType,
        "set":                spec.set,
        "subSet":             spec.subSet,
        "variation":          spec.variation,
        "treatment":          spec.treatment,
        "release":            spec.release,
        "element":            spec.element,
        "power":              spec.power,
        "playCost":           spec.playCost,
        "playAbility":        spec.playAbility,
        "athleteInspiration": spec.athleteInspiration,
        "isInspiredInk":      spec.isInspiredInk,
        "rookieInspired":     spec.rookieInspired,
        "isBonusPlay":        spec.isBonusPlay,
        "isHTD":              spec.isHTD,
        "dbs":                spec.dbs,
        "dbsTier":            spec.dbsTier,
        "imageFile":          image_filename,
        "imageSource":null if image_filename else None,
        "imageAvailable":     image_filename is not None,
        "radishUrl":          None,
        "searchTokens":       _tokens(spec),
    }
    record["bobaId"] = boba_id(record)
    return record


def _tokens(spec: NewCardSpec) -> str:
    """Lowercased space-joined search tokens. The existing catalog
    follows this shape — keeps search-index.json consistent if it's
    rebuilt downstream."""
    bits = [
        spec.hero, spec.name, spec.cardNumber, spec.set, spec.subSet,
        spec.treatment, spec.variation, spec.athleteInspiration or "",
        spec.element, str(spec.power) if spec.power is not None else "",
    ]
    return " ".join(b for b in bits if b).lower()


def patch_bundle(path: Path, new_records: list[dict], dry_run: bool) -> tuple[int, int]:
    """Append new records to a bundle. Returns (added, already_present).

    A "duplicate" by bobaId means the importer was re-run — skip
    silently (idempotent)."""
    if not path.exists():
        print(f"  skip {path.name}: not present")
        return (0, 0)
    data = json.loads(path.read_text())
    cards = data["cards"] if isinstance(data, dict) and "cards" in data else data
    existing = {(c.get("bobaId") or boba_id(c)) for c in cards}
    added = 0
    already = 0
    for rec in new_records:
        if rec["bobaId"] in existing:
            already += 1
            continue
        cards.append(rec)
        existing.add(rec["bobaId"])
        added += 1
    if not dry_run and added > 0:
        path.write_text(json.dumps(data if isinstance(data, dict) and "cards" in data else cards,
                                   ensure_ascii=False, indent=2) + "\n")
    return (added, already)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="Write R2 + catalog bundles (omit for dry-run)")
    args = ap.parse_args()
    dry = not args.apply

    # Validate uniqueness of all proposed bobaIds against the current
    # catalog BEFORE doing any work.
    cards_path = REPO / "assets" / "data" / "cards.json"
    existing_bids = set()
    for c in json.loads(cards_path.read_text()):
        bid = c.get("bobaId") or boba_id(c)
        existing_bids.add(bid)

    proposed: list[tuple[NewCardSpec, dict, Optional[bytes], Optional[bytes], Optional[str]]] = []
    for spec in SPECS:
        # Build the record (without image yet) to compute the bobaId.
        provisional = build_card_record(spec, image_filename=None)
        bid = provisional["bobaId"]
        if bid in existing_bids:
            print(f"  skip {bid}: already in catalog")
            continue

        if spec.source_png is None:
            print(f"  add  {bid}: NO image (queued for auto-pipeline)")
            record = build_card_record(spec, image_filename=None)
            proposed.append((spec, record, None, None, None))
            continue

        if not spec.source_png.exists():
            print(f"  skip {bid}: source PNG missing at {spec.source_png}")
            continue

        full_bytes, thumb_bytes = generate_tiers(spec.source_png)
        image_filename = safe_filename_for_boba_id(bid)
        record = build_card_record(spec, image_filename=image_filename)
        proposed.append((spec, record, full_bytes, thumb_bytes, image_filename))
        print(f"  add  {bid}: image → {image_filename} "
              f"(full {len(full_bytes)//1024} KB, thumb {len(thumb_bytes)//1024} KB)")

    if not proposed:
        print("\nNothing to add. Catalog already contains all targets.")
        return

    new_records = [rec for (_, rec, _, _, _) in proposed]

    if dry:
        print(f"\nDRY RUN: would add {len(new_records)} card(s) and upload "
              f"{sum(1 for p in proposed if p[2] is not None)} image(s).")
        print("Run with --apply to commit.")
        return

    # R2 upload (only when an image is supplied).
    bucket = os.environ.get("R2_BUCKET", "boba-card-images")
    r2_uploads_needed = [(p[4], p[2], p[3]) for p in proposed if p[2] is not None]
    if r2_uploads_needed:
        r2 = make_r2_client()
        for fname, full, thumb in r2_uploads_needed:
            full_key = f"full/{fname}"
            thumb_key = f"thumbs/{fname}"
            f_status = upload_with_guard(r2, bucket, full_key, full)
            t_status = upload_with_guard(r2, bucket, thumb_key, thumb)
            print(f"    R2 full/{fname}: {f_status}    thumbs/{fname}: {t_status}")
            if f_status == "exists" or t_status == "exists":
                print(f"    ⚠ ABORT: target keys already populated — "
                      f"refusing to overwrite. Check catalog vs R2.")
                sys.exit(1)

    # Patch every bundle.
    for path in BUNDLES:
        added, dup = patch_bundle(path, new_records, dry_run=False)
        print(f"  {path.name}: +{added} added, {dup} already present")

    print(f"\nDone. Added {len(new_records)} card(s) across {len(BUNDLES)} bundle(s).")


if __name__ == "__main__":
    main()
