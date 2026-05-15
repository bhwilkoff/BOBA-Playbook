#!/usr/bin/env python3
"""
merge_approved_additions.py — Promote admin-approved card additions
into the catalog + R2.

Polls Supabase for rows in card_corrections where:
  kind   = 'addition'
  status = 'approved'
  merged_at IS NULL          ← gate against re-merging

For each row:
  1. Parse the full card spec out of the `corrections` jsonb column.
  2. Re-compute the bobaId via scripts/boba_id.py — defends against a
     malicious or stale client. The DB's boba_id column is informational.
  3. Verify the bobaId isn't already in cards.json.
  4. If `image_storage_path` is set, fetch the image from the Supabase
     Storage `mod-card-images` bucket, re-encode to WebP tiers per
     DECISIONS.md #008, HEAD-check then PUT to R2 per DECISIONS.md #026.
  5. Append the new card record to all 5 catalog bundles.
  6. PATCH the card_corrections row with merged_at = now() so we
     don't re-process it next run.

Shares the WebP encoding + R2 upload helpers with scripts/import_new_cards.py
to keep the two paths in lockstep on image specs.

USAGE
─────
    python scripts/merge_approved_additions.py           # dry-run, no writes
    python scripts/merge_approved_additions.py --apply   # writes catalog + R2 + DB

ENV (required for --apply when uploading images):
    SUPABASE_URL, SUPABASE_SERVICE_KEY
    R2_ACCOUNT_ID, R2_ACCESS_KEY, R2_SECRET_KEY, R2_BUCKET
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
from pathlib import Path
from typing import Any, Optional

import boto3
import requests
from botocore.config import Config
from dotenv import load_dotenv
from PIL import Image
from supabase import Client, create_client

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))
from boba_id import boba_id  # noqa: E402

load_dotenv(REPO / ".env")

BUNDLES: list[Path] = [
    REPO / "assets" / "data" / "cards.json",
    REPO / "assets" / "data" / "cards-slim.json",
    REPO / "assets" / "data" / "cards-head.json",
    REPO / "BOBAPlaybook" / "display-cards.json",
    REPO / "BOBAPlaybook" / "cards-head.json",
]

FULL_MAX_DIM  = 1200
FULL_QUALITY  = 75
THUMB_MAX_DIM = 200
THUMB_QUALITY = 60

# Supabase Storage bucket where ModAddCardSheet uploads moderator
# images. The mod-card-images bucket is shared with ModCardEditSheet's
# replace-image flow.
SUPABASE_BUCKET = "mod-card-images"


def supabase_client() -> Client:
    return create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def r2_client():
    return boto3.client(
        "s3",
        endpoint_url=f"https://{os.environ['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",
        aws_access_key_id=os.environ["R2_ACCESS_KEY"],
        aws_secret_access_key=os.environ["R2_SECRET_KEY"],
        config=Config(signature_version="s3v4", retries={"max_attempts": 3}),
    )


def fetch_pending(sb: Client) -> list[dict]:
    """Fetch approved additions that haven't been merged yet.

    Uses a NULL filter on `merged_at`. If your migration doesn't have
    that column yet, run:
       ALTER TABLE card_corrections ADD COLUMN merged_at timestamptz;
    """
    res = (sb.table("card_corrections")
             .select("id,card_number,corrections,notes,boba_id,image_storage_path,status,kind,merged_at")
             .eq("kind", "addition")
             .eq("status", "approved")
             .is_("merged_at", "null")
             .order("created_at")
             .execute())
    return res.data or []


def safe_filename_for_boba_id(bid: str) -> str:
    out = []
    for ch in bid:
        if ch.isalnum() or ch in ("-", "_", "."):
            out.append(ch)
        else:
            out.append("_")
    return "".join(out).rstrip("_-") + ".webp"


def fetch_image_from_supabase(storage_path: str) -> Optional[bytes]:
    """Read the image bytes from `mod-card-images/{storage_path}` via
    the Supabase Storage REST API. Returns None if the path is empty
    or the file is missing."""
    if not storage_path:
        return None
    base = os.environ["SUPABASE_URL"].rstrip("/")
    key  = os.environ["SUPABASE_SERVICE_KEY"]
    url = f"{base}/storage/v1/object/{SUPABASE_BUCKET}/{storage_path}"
    resp = requests.get(url, headers={
        "apikey": key,
        "Authorization": f"Bearer {key}",
    })
    if resp.status_code == 404:
        return None
    resp.raise_for_status()
    return resp.content


def generate_tiers(src_bytes: bytes) -> tuple[bytes, bytes]:
    src = Image.open(io.BytesIO(src_bytes)).convert("RGB")
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
    """HEAD-check before PUT — refuse to overwrite (R2 has no
    version history; DECISIONS.md #026)."""
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


def build_full_record(spec: dict, image_filename: Optional[str], bid: str) -> dict:
    """Compose the canonical cards.json record from the spec the mod
    submitted. Fills in the structural defaults the form may have
    skipped (radishUrl, imageSource, etc.) so every bundle entry has
    the same field set as the existing 17,968 cards."""
    record = {
        "cardNumber":         spec.get("cardNumber", ""),
        "name":               spec.get("name", spec.get("hero", "")),
        "hero":               spec.get("hero", ""),
        "cardType":           spec.get("cardType", "Hero"),
        "set":                spec.get("set", ""),
        "subSet":             spec.get("subSet", ""),
        "variation":          spec.get("variation", ""),
        "treatment":          spec.get("treatment", ""),
        "release":            spec.get("release", ""),
        "element":            spec.get("element", "NONE"),
        "power":              spec.get("power"),
        "playCost":           spec.get("playCost"),
        "playAbility":        spec.get("playAbility"),
        "athleteInspiration": spec.get("athleteInspiration"),
        "isInspiredInk":      bool(spec.get("isInspiredInk", False)),
        "rookieInspired":     bool(spec.get("rookieInspired", False)),
        "isBonusPlay":        bool(spec.get("isBonusPlay", False)),
        "isHTD":              bool(spec.get("isHTD", False)),
        "dbs":                spec.get("dbs"),
        "dbsTier":            spec.get("dbsTier"),
        "imageFile":          image_filename,
        "imageSource":        "mod_upload" if image_filename else None,
        "imageAvailable":     image_filename is not None,
        "radishUrl":          None,
        "bobaId":             bid,
    }
    # searchTokens — same shape as the rest of the catalog.
    tokens = []
    for k in ("hero", "name", "cardNumber", "set", "subSet",
              "treatment", "variation", "athleteInspiration",
              "element"):
        v = record.get(k)
        if v: tokens.append(str(v))
    if record["power"] is not None:
        tokens.append(str(record["power"]))
    record["searchTokens"] = " ".join(tokens).lower()
    return record


def patch_bundle(path: Path, new_records: list[dict], dry_run: bool) -> tuple[int, int]:
    if not path.exists():
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


def mark_merged(sb: Client, row_id: str):
    sb.table("card_corrections").update({"merged_at": "now()"}).eq("id", row_id).execute()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true",
                    help="Write catalog bundles, upload to R2, mark rows merged. "
                         "Omit for dry-run.")
    args = ap.parse_args()
    dry = not args.apply

    sb = supabase_client()
    pending = fetch_pending(sb)
    if not pending:
        print("No approved additions awaiting merge.")
        return

    # Load existing catalog bobaIds for uniqueness defense.
    cards_path = REPO / "assets" / "data" / "cards.json"
    existing: set[str] = set()
    for c in json.loads(cards_path.read_text()):
        existing.add(c.get("bobaId") or boba_id(c))

    bucket = os.environ.get("R2_BUCKET", "boba-card-images")
    r2 = None if dry else r2_client()

    new_records: list[dict] = []
    merged_ids: list[str] = []
    for row in pending:
        spec = row.get("corrections") or {}
        bid = boba_id(spec)  # recompute server-side
        if bid in existing:
            print(f"  skip {bid}: already in catalog (row {row['id']})")
            merged_ids.append(row["id"])  # still mark merged so we don't re-poll
            continue

        image_filename: Optional[str] = None
        if row.get("image_storage_path"):
            img_bytes = fetch_image_from_supabase(row["image_storage_path"])
            if img_bytes is None:
                print(f"  warn {bid}: image_storage_path={row['image_storage_path']} missing — adding without image")
            else:
                full, thumb = generate_tiers(img_bytes)
                fname = safe_filename_for_boba_id(bid)
                if not dry:
                    f_status = upload_with_guard(r2, bucket, f"full/{fname}",   full)
                    t_status = upload_with_guard(r2, bucket, f"thumbs/{fname}", thumb)
                    if f_status == "exists" or t_status == "exists":
                        print(f"  ⚠ skip {bid}: R2 key already populated (full={f_status} thumb={t_status})")
                        continue
                image_filename = fname

        rec = build_full_record(spec, image_filename, bid)
        new_records.append(rec)
        existing.add(bid)
        merged_ids.append(row["id"])
        print(f"  add  {bid}  (image={'yes' if image_filename else 'no'})")

    if not new_records:
        print("\nNothing to add.")
        return

    if dry:
        print(f"\nDRY RUN: would add {len(new_records)} card(s) "
              f"and mark {len(merged_ids)} row(s) merged.")
        return

    # Patch bundles.
    for path in BUNDLES:
        added, dup = patch_bundle(path, new_records, dry_run=False)
        print(f"  {path.name}: +{added} added, {dup} already present")

    # Mark each source row merged.
    for rid in merged_ids:
        mark_merged(sb, rid)

    print(f"\nDone. Added {len(new_records)} card(s); marked {len(merged_ids)} addition row(s) merged.")


if __name__ == "__main__":
    main()
