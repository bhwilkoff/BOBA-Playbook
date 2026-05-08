#!/usr/bin/env python3
"""
import_research_queue.py

One-time migration: pulls the existing eBay review queue from Ben's
research folder into Supabase pipeline_image_candidates and uploads the
cropped images to R2 staging.

This is the LAST script that ever runs on Ben's local Mac. After it
finishes, the entire pipeline operates from GitHub Actions + Cloudflare
Workers — no local-Mac dependency.

Why this matters: the imported corpus has implicit labels we'll use to
calibrate Stage B's score thresholds in Phase 4:

  - ebay-verified/images/      → state='accepted'    (positive: human-OK'd)
  - ebay-review/needs-review/  → state='cropped'     (un-scored, ready for Stage B)
  - ebay-review/quarantine/    → state='quarantined' (negative: Vision OCR rejected)
  - ebay-review/rejected/      → state='rejected'    (negative: human rejected)
  - ebay-review/reclaim/       → state='cropped'     (OCR-reclassified, ready)

Idempotent on re-run via UNIQUE(source, source_id) — repeated invocations
skip rows that already exist.

USAGE
─────
    # 1. Fill .env at repo root (see pipeline/docs/SETUP.md for the keys)
    # 2. pip install -r pipeline/scripts/requirements.txt
    # 3. Apply the Supabase migration (see pipeline/migrations/README.md)
    # 4. Run with --dry-run first to preview the work:

    python pipeline/scripts/import_research_queue.py --dry-run

    # 5. Then run for real, ramping the limit:

    python pipeline/scripts/import_research_queue.py --limit 100   # smoke test
    python pipeline/scripts/import_research_queue.py               # full run
"""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

# Third-party — see requirements.txt
import boto3                                 # R2 (S3-compatible)
from botocore.config import Config
from dotenv import load_dotenv               # auto-loads .env from repo root
from supabase import Client, create_client   # Supabase client

# Load .env from the BOBA-Playbook repo root (two levels up from
# this script: pipeline/scripts/ → repo root). load_dotenv() is a
# no-op if the file doesn't exist, so CI runs (which use GH Actions
# secrets directly) still work fine.
load_dotenv(Path(__file__).resolve().parents[2] / ".env")


# ─── Defaults ─────────────────────────────────────────────────────────────

DEFAULT_RESEARCH_DIR = Path(
    "/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research"
)

# Where in R2 the migrated images land. Prefix exists in boba-card-images
# bucket alongside thumbs/ and full/ — staging is for in-flight pipeline
# work, not user-facing CDN delivery.
R2_STAGING_PREFIX = "staging/research-queue"

# Per-image upload concurrency. R2 free tier handles plenty; this just
# prevents us from saturating the user's home connection.
UPLOAD_WORKERS = 8

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}


# ─── State mapping ────────────────────────────────────────────────────────

STATE_BY_RELATIVE_ROOT = {
    # ebay-verified/images was historically state='accepted' on the
    # assumption that human approval implied a final commit-ready
    # state. That broke Stage C — recognized_boba_id was set to the
    # filename slug, which doesn't match the canonical bobaId format
    # in cards.json. Stage C uploaded R2 files at slug-style names
    # that no card record references. ALL imports now go to 'cropped'
    # so Stage B does the canonical recognition pass; humans approved
    # the IMAGE/CARD match, not the filename's bobaId format.
    "ebay-verified/images":           "cropped",
    "ebay-review/needs-review":       "cropped",
    "ebay-review/quarantine":         "quarantined",
    "ebay-review/rejected":           "rejected",
    "ebay-review/reclaim":            "cropped",
}


# ─── Data classes ─────────────────────────────────────────────────────────

@dataclass
class Candidate:
    """One image in the research queue, ready to be migrated."""
    local_path:      Path
    relative_path:   str          # path under the research dir, used as source_id
    state:           str
    target_boba_id:  Optional[str]
    recognized_boba_id: Optional[str]
    image_md5:       Optional[str] = None
    r2_key:          Optional[str] = None
    metadata:        dict          = field(default_factory=dict)


# ─── Discovery: walk the research folder ──────────────────────────────────

def discover_candidates(research_dir: Path, limit: Optional[int] = None) -> list[Candidate]:
    """Walk the research folder; build a Candidate for every image found."""
    candidates: list[Candidate] = []

    for relative_root, state in STATE_BY_RELATIVE_ROOT.items():
        root_dir = research_dir / relative_root
        if not root_dir.is_dir():
            print(f"  skip {relative_root}: not present")
            continue

        scanned = 0
        for path in root_dir.rglob("*"):
            if not path.is_file() or path.suffix.lower() not in IMAGE_EXTENSIONS:
                continue

            relative = path.relative_to(research_dir).as_posix()
            target_boba_id, recognized_boba_id = infer_boba_ids(path, root_dir, state)

            candidates.append(Candidate(
                local_path=path,
                relative_path=relative,
                state=state,
                target_boba_id=target_boba_id,
                recognized_boba_id=recognized_boba_id,
            ))
            scanned += 1

            if limit and len(candidates) >= limit:
                print(f"  hit --limit cap of {limit} — stopping discovery")
                return candidates

        print(f"  found {scanned} in {relative_root}")

    return candidates


def infer_boba_ids(path: Path, root_dir: Path, state: str) -> tuple[Optional[str], Optional[str]]:
    """
    Best-effort inference of (target_boba_id, recognized_boba_id) from path.

    Conventions in the research folder (verified empirically 2026-05-07):

      ebay-verified/images/{bobaIdSlug}.{jpg,webp,png}
        → flat layout, file stem IS the bobaId slug

      ebay-review/{needs-review,quarantine,reclaim,rejected}/
          {bobaIdSlug}__{eBayListingId}__{ordinal}.jpg
        → flat layout, file stem encodes the bobaId before the FIRST '__'

    target_boba_id is the slug-form hint from the filename — used only
    as scrape-time targeting context, not as a final identifier.
    recognized_boba_id is intentionally NEVER set by import. ALL
    canonical bobaId assignment runs through Stage B's ScanMatching
    so the result is byte-identical to the format cards.json uses
    (no slug-vs-canonical mismatch downstream). Even ebay-verified
    images go through Stage B — humans approved that the IMAGE matches
    the card, not that the filename is in canonical form.
    """
    if state == "accepted":
        # Flat: ebay-verified/images/{slug}.jpg — slug-form target only
        return (path.stem, None)

    if state in ("cropped", "quarantined", "rejected"):
        # Flat: ebay-review/{state-root}/{slug}__{listing-id}__{N}.jpg
        # Take everything before the FIRST '__' as the target slug.
        stem = path.stem
        if "__" in stem:
            slug = stem.split("__", 1)[0]
            return (slug, None)
        return (stem, None)

    return (None, None)


# ─── Hashing + R2 upload ──────────────────────────────────────────────────

def md5_file(path: Path, chunk_size: int = 65536) -> str:
    h = hashlib.md5()
    with path.open("rb") as f:
        while chunk := f.read(chunk_size):
            h.update(chunk)
    return h.hexdigest()


def make_r2_client(account_id: str, access_key: str, secret_key: str):
    return boto3.client(
        "s3",
        endpoint_url=f"https://{account_id}.r2.cloudflarestorage.com",
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(signature_version="s3v4", retries={"max_attempts": 3}),
    )


def r2_key_for(candidate: Candidate) -> str:
    """staging/research-queue/{state}/{md5-prefix}/{filename}"""
    md5 = candidate.image_md5 or "unhashed"
    return f"{R2_STAGING_PREFIX}/{candidate.state}/{md5[:2]}/{md5}-{candidate.local_path.name}"


def upload_one(r2_client, bucket: str, candidate: Candidate, dry_run: bool) -> Candidate:
    candidate.image_md5 = md5_file(candidate.local_path)
    candidate.r2_key = r2_key_for(candidate)

    if dry_run:
        return candidate

    # Idempotent: skip upload if the object already exists with the same
    # md5 (R2 doesn't expose md5 in HEAD without ETag → we trust the key
    # collision check)
    try:
        r2_client.head_object(Bucket=bucket, Key=candidate.r2_key)
        # Already uploaded
        return candidate
    except r2_client.exceptions.ClientError:
        pass

    content_type = {
        ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
        ".png": "image/png",  ".webp": "image/webp",
    }.get(candidate.local_path.suffix.lower(), "application/octet-stream")

    with candidate.local_path.open("rb") as f:
        r2_client.put_object(
            Bucket=bucket,
            Key=candidate.r2_key,
            Body=f,
            ContentType=content_type,
        )
    return candidate


# ─── Supabase upserts ─────────────────────────────────────────────────────

def upsert_run(client: Client, dry_run: bool) -> Optional[str]:
    if dry_run:
        return None
    res = client.table("pipeline_runs").insert({
        "run_type": "backfill",
        "summary": {"description": "research-queue migration — initial import"},
    }).execute()
    return res.data[0]["id"]


def upsert_candidates(
    client: Client,
    candidates: list[Candidate],
    run_id: Optional[str],
    dry_run: bool,
) -> dict[str, int]:
    counts = {"inserted": 0, "skipped": 0, "errors": 0}

    rows = [
        {
            "source": "research_queue",
            "source_url": "local://research-folder",
            "source_id": c.relative_path,
            "source_metadata": c.metadata,
            "target_boba_id": c.target_boba_id,
            "recognized_boba_id": c.recognized_boba_id,
            "raw_image_r2_key": c.r2_key,
            "crop_image_r2_key": c.r2_key,  # research data is already cropped
            "image_md5": c.image_md5,
            "state": c.state,
            "discovered_by_run_id": run_id,
        }
        for c in candidates
    ]

    if dry_run:
        counts["inserted"] = len(rows)
        return counts

    # Upsert in batches of 500 to stay well under PostgREST request limits
    BATCH = 500
    for i in range(0, len(rows), BATCH):
        chunk = rows[i:i + BATCH]
        try:
            res = (client
                .table("pipeline_image_candidates")
                .upsert(chunk, on_conflict="source,source_id", ignore_duplicates=True)
                .execute())
            counts["inserted"] += len(res.data) if res.data else 0
            counts["skipped"]  += len(chunk) - (len(res.data) if res.data else 0)
        except Exception as e:
            print(f"  ! batch {i}-{i+len(chunk)} error: {e}")
            counts["errors"]   += len(chunk)

    return counts


def finalize_run(client: Client, run_id: Optional[str], counts: dict[str, int], dry_run: bool):
    if dry_run or not run_id:
        return
    client.table("pipeline_runs").update({
        "finished_at":          "now()",
        "candidates_processed": counts["inserted"] + counts["skipped"],
        "summary": {
            "inserted": counts["inserted"],
            "skipped":  counts["skipped"],
            "errors":   counts["errors"],
        },
    }).eq("id", run_id).execute()


# ─── Main ─────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--research-dir",
                    default=str(DEFAULT_RESEARCH_DIR),
                    help="Path to the BoBA Research folder")
    ap.add_argument("--limit", type=int, default=None,
                    help="Stop after N candidates (smoke testing)")
    ap.add_argument("--dry-run", action="store_true",
                    help="Discover + count, don't upload or insert")
    args = ap.parse_args()

    research_dir = Path(args.research_dir).expanduser().resolve()
    if not research_dir.is_dir():
        sys.exit(f"research dir not found: {research_dir}")

    # ─── Env ──
    supabase_url     = os.environ.get("SUPABASE_URL")
    supabase_key     = os.environ.get("SUPABASE_SERVICE_KEY")
    r2_account_id    = os.environ.get("R2_ACCOUNT_ID")
    r2_access_key    = os.environ.get("R2_ACCESS_KEY")
    r2_secret_key    = os.environ.get("R2_SECRET_KEY")
    r2_bucket        = os.environ.get("R2_BUCKET", "boba-card-images")

    missing = [k for k, v in {
        "SUPABASE_URL":          supabase_url,
        "SUPABASE_SERVICE_KEY":  supabase_key,
        "R2_ACCOUNT_ID":         r2_account_id,
        "R2_ACCESS_KEY":         r2_access_key,
        "R2_SECRET_KEY":         r2_secret_key,
    }.items() if not v]
    if missing and not args.dry_run:
        sys.exit(f"missing env: {', '.join(missing)} — see pipeline/docs/SETUP.md")

    print(f"research dir: {research_dir}")
    print(f"R2 bucket:    {r2_bucket}/{R2_STAGING_PREFIX}/")
    print(f"dry run:      {args.dry_run}")
    if args.limit:
        print(f"limit:        {args.limit}")
    print()

    # ─── Discover ──
    print("→ discovering candidates")
    candidates = discover_candidates(research_dir, limit=args.limit)
    print(f"  {len(candidates)} candidates total")
    if not candidates:
        sys.exit("nothing to import")

    by_state: dict[str, int] = {}
    for c in candidates:
        by_state[c.state] = by_state.get(c.state, 0) + 1
    print(f"  by state: " + ", ".join(f"{s}={n}" for s, n in sorted(by_state.items())))
    print()

    # ─── Hash + Upload to R2 ──
    if args.dry_run:
        print(f"→ hashing only (dry-run — R2 upload skipped) ({UPLOAD_WORKERS} workers)")
    else:
        print(f"→ hashing + uploading to R2 ({UPLOAD_WORKERS} workers)")
    r2_client = (None if args.dry_run else
                 make_r2_client(r2_account_id, r2_access_key, r2_secret_key))

    t0 = time.time()
    done = 0
    with ThreadPoolExecutor(max_workers=UPLOAD_WORKERS) as pool:
        futures = [pool.submit(upload_one, r2_client, r2_bucket, c, args.dry_run)
                   for c in candidates]
        for fut in as_completed(futures):
            try:
                fut.result()
            except Exception as e:
                print(f"  ! upload error: {e}")
            done += 1
            if done % 100 == 0:
                rate = done / (time.time() - t0)
                print(f"  {done}/{len(candidates)}  ({rate:.1f}/s)")

    print(f"  uploaded {done}/{len(candidates)} in {time.time() - t0:.1f}s")
    print()

    # ─── Insert into Supabase ──
    print("→ writing to Supabase pipeline_image_candidates")
    supabase = (None if args.dry_run else
                create_client(supabase_url, supabase_key))
    run_id = upsert_run(supabase, args.dry_run) if supabase else None
    counts = upsert_candidates(supabase, candidates, run_id, args.dry_run)
    finalize_run(supabase, run_id, counts, args.dry_run)

    print(f"  inserted: {counts['inserted']}")
    print(f"  skipped:  {counts['skipped']}  (already migrated)")
    print(f"  errors:   {counts['errors']}")
    print()
    if not args.dry_run and run_id:
        print(f"run_id: {run_id}")
    print("done.")


if __name__ == "__main__":
    main()
