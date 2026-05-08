#!/usr/bin/env python3
"""
stage_a_scrape_discord.py — Stage A: source candidates from a local
DiscordChatExporter dump of the BoBA Discord.

This is a ONE-TIME, LOCAL-ONLY sourcer (Discord CDN URLs are
short-lived signed URLs that expire ~24h after the export is generated;
the dump is also not a regenerable resource we'd run on a cron). Unlike
BV / eBay / Radish — which Stage A targets per missing bobaId — Discord
attachments are blind ingests: we don't know which card a given user
photo depicts until Stage B's Vision pipeline identifies it.

Output state per attachment:
  - source            = "discord"
  - source_id         = "{channel_id}-{message_id}-{attachment_id}"
  - target_boba_id    = NULL  ← unknown; no target-match AUTO path
  - state             = "cropped"

Stage B's strict score-only AUTO path (score ≥ 4.5 + margin gates)
handles unknown-target candidates. Stage C's have_art filter still
prevents shipping for already-imaged cards.

DISCORD URL EXPIRY
──────────────────
Since 2024 Discord enforces ~24h-signed URLs on every CDN attachment.
A JSON-only DiscordChatExporter dump becomes unrecoverable as soon as
the signature expires.

The fix is the `--media` flag. It downloads attachments to a sibling
`*_Files/` directory and rewrites `attachments[].url` in the JSON to
the local file path:

    dotnet DiscordChatExporter.Cli.dll export \\
        -t <TOKEN> -c <CHANNEL_ID> --media -f Json -o exports/

This sourcer treats any non-http `url` as a filesystem path resolved
relative to the JSON file's directory. So the same script works for
both fresh-and-still-signed URLs AND `--media` local exports.

USAGE
─────
    # 1. Make sure .env is filled at repo root.
    # 2. Re-run the Discord export with --media (see above).
    # 3. Dry-run to verify shape + counts:
    python pipeline/scripts/stage_a_scrape_discord.py --dry-run

    # 4. Run for real (download + upload + insert):
    python pipeline/scripts/stage_a_scrape_discord.py

ENV
───
SUPABASE_URL · SUPABASE_SERVICE_KEY · R2_ACCOUNT_ID · R2_ACCESS_KEY ·
R2_SECRET_KEY  (R2_BUCKET defaults to "boba-card-images")
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import boto3
import requests
from botocore.config import Config
from dotenv import load_dotenv
from supabase import Client, create_client

load_dotenv(Path(__file__).resolve().parents[2] / ".env")


# ─── Config ───────────────────────────────────────────────────────────────

DEFAULT_EXPORTS_DIR = Path(
    "/Users/bhwilkoff/Documents/Claude/Projects/"
    "Bo Jackson Battle Arena Research/discord-exports"
)
CDN_STAGING_PREFIX = "staging/scrape/discord"
USER_AGENT         = "Mozilla/5.0 (compatible; BoBA-Pipeline/1.0)"
IMG_EXTENSIONS     = {".jpg", ".jpeg", ".png", ".webp", ".heic"}

# Most card photos sit between 50 KB (small thumbnail) and 12 MB
# (untouched iPhone photo). Outside this range we're either dealing with
# a 1×1 transparent pixel, a server-side compressed avatar, or a video
# masquerading as an image. Stage B can't recover from either.
MIN_BYTES = 50_000
MAX_BYTES = 12_000_000

# Max concurrent downloads — Discord CDN is generous but we don't need
# to hammer it; this is a one-off script, throughput isn't the concern.
DOWNLOAD_WORKERS = 8


# ─── Helpers ──────────────────────────────────────────────────────────────

def make_r2_client(account_id: str, access_key: str, secret_key: str):
    return boto3.client(
        "s3",
        endpoint_url=f"https://{account_id}.r2.cloudflarestorage.com",
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(signature_version="s3v4", retries={"max_attempts": 3}),
    )


@dataclass
class Attachment:
    """Flat shape for a Discord attachment we'll try to ingest.

    `url` may be either a remote URL or a filesystem path. When DCE was
    run with --media the JSON's url field is rewritten to a local path
    relative to the JSON file; we resolve that against `json_dir`.
    """
    channel_name: str
    channel_id:   str
    message_id:   str
    attachment_id: str
    url:          str
    file_name:    str
    file_ext:     str
    declared_size: int
    timestamp:    str
    json_dir:     Path

    @property
    def source_id(self) -> str:
        return f"{self.channel_id}-{self.message_id}-{self.attachment_id}"

    @property
    def is_local(self) -> bool:
        """Url field may be relative path, file:// URL, or http(s)."""
        return not self.url.lower().startswith(("http://", "https://"))

    def local_path(self) -> Optional[Path]:
        """Resolve a local-file url to an absolute Path, if applicable."""
        if not self.is_local:
            return None
        u = self.url
        if u.startswith("file://"):
            u = u[len("file://"):]
        p = Path(u)
        if not p.is_absolute():
            p = (self.json_dir / p).resolve()
        return p


def collect_attachments(exports_dir: Path) -> list[Attachment]:
    """Walk every *.json export in `exports_dir` and pull out every
    image attachment that has a plausible filesize/extension. Embeds
    are intentionally skipped — they're eBay listing previews and
    other off-platform refs that already arrive via dedicated sourcers."""
    out: list[Attachment] = []
    seen_ids: set[str] = set()

    for jf in sorted(exports_dir.glob("*.json")):
        try:
            data = json.loads(jf.read_text())
        except Exception as e:
            print(f"  ! skipping {jf.name}: {e}")
            continue

        chan = (data.get("channel") or {})
        chan_name = chan.get("name") or jf.stem
        chan_id   = chan.get("id")   or ""

        for msg in data.get("messages", []) or []:
            msg_id = msg.get("id") or ""
            ts     = msg.get("timestamp") or ""
            for att in msg.get("attachments", []) or []:
                att_id  = att.get("id") or ""
                url     = att.get("url") or ""
                fname   = att.get("fileName") or ""
                size    = int(att.get("fileSizeBytes") or 0)
                if not (att_id and url and fname):
                    continue

                ext = Path(fname).suffix.lower()
                if ext not in IMG_EXTENSIONS:
                    continue
                if size and (size < MIN_BYTES or size > MAX_BYTES):
                    continue

                a = Attachment(
                    channel_name=chan_name,
                    channel_id=chan_id,
                    message_id=msg_id,
                    attachment_id=att_id,
                    url=url,
                    file_name=fname,
                    file_ext=ext,
                    declared_size=size,
                    timestamp=ts,
                    json_dir=jf.parent,
                )
                if a.source_id in seen_ids:
                    continue
                seen_ids.add(a.source_id)
                out.append(a)

    return out


def existing_source_ids(supabase: Client, source_ids: list[str]) -> set[str]:
    """Pre-filter against rows that already exist so we don't waste
    bandwidth re-downloading attachments we've already ingested."""
    existing: set[str] = set()
    CHUNK = 50
    for i in range(0, len(source_ids), CHUNK):
        chunk = source_ids[i:i + CHUNK]
        res = (supabase.table("pipeline_image_candidates")
               .select("source_id")
               .eq("source", "discord")
               .in_("source_id", chunk)
               .execute()).data or []
        for r in res:
            if r.get("source_id"):
                existing.add(r["source_id"])
    return existing


def download_one(att: Attachment) -> Optional[tuple[Attachment, bytes, str]]:
    """Returns (attachment, image_bytes, md5_hex) or None on failure.

    Local exports (DCE --media) read straight off disk. Remote URLs
    fetch via HTTP; Discord's signed-URL expiry produces 403/404/410
    — those are silent-skip (expected for any attachment older than
    ~24h from when the export ran)."""
    body: bytes
    if att.is_local:
        p = att.local_path()
        if not p or not p.is_file():
            return None
        try:
            body = p.read_bytes()
        except Exception:
            return None
    else:
        try:
            resp = requests.get(att.url,
                                headers={"User-Agent": USER_AGENT},
                                timeout=20)
            if resp.status_code in (403, 404, 410):
                return None  # signed URL expired; silent skip
            resp.raise_for_status()
            body = resp.content
        except Exception:
            return None

    if len(body) < MIN_BYTES or len(body) > MAX_BYTES:
        return None
    md5 = hashlib.md5(body).hexdigest()
    return (att, body, md5)


def content_type_for(ext: str) -> str:
    return {
        ".jpg":  "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png":  "image/png",
        ".webp": "image/webp",
        ".heic": "image/heic",
    }.get(ext, "application/octet-stream")


# ─── Main ─────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--exports-dir", default=str(DEFAULT_EXPORTS_DIR),
                    help="Directory containing DiscordChatExporter *.json files")
    ap.add_argument("--limit", type=int, default=None,
                    help="Cap candidates inserted this run (testing)")
    ap.add_argument("--dry-run", action="store_true",
                    help="Plan only — no downloads, no R2 puts, no DB writes")
    args = ap.parse_args()

    exports_dir = Path(args.exports_dir).expanduser()
    if not exports_dir.is_dir():
        print(f"!! exports dir not found: {exports_dir}", file=sys.stderr)
        sys.exit(2)

    # ─── Connect ──
    supabase: Client = create_client(
        os.environ["SUPABASE_URL"].strip(),
        os.environ["SUPABASE_SERVICE_KEY"].strip(),
    )
    r2 = None
    bucket = os.environ.get("R2_BUCKET", "boba-card-images").strip()
    if not args.dry_run:
        r2 = make_r2_client(
            os.environ["R2_ACCOUNT_ID"].strip(),
            os.environ["R2_ACCESS_KEY"].strip(),
            os.environ["R2_SECRET_KEY"].strip(),
        )

    # ─── Run header ──
    run_id = None
    if not args.dry_run:
        run = supabase.table("pipeline_runs").insert({
            "run_type": "scrape",
            "gh_actions_run_id": os.environ.get("GITHUB_RUN_ID"),
            "summary": {"source": "discord-export"},
        }).execute()
        run_id = run.data[0]["id"]
        print(f"run_id: {run_id}")

    # ─── Collect attachments ──
    print(f"\nscanning {exports_dir} …")
    atts = collect_attachments(exports_dir)
    print(f"  total image attachments:   {len(atts):,}")
    n_local = sum(1 for a in atts if a.is_local)
    print(f"  local files (--media):     {n_local:,}")
    print(f"  remote (signed) URLs:      {len(atts) - n_local:,}")
    if n_local == 0 and atts:
        print(
            "\n  ⚠ Every attachment URL is a signed Discord CDN link.\n"
            "    Discord rotates these every ~24h since 2024 — if this\n"
            "    export is older than a day, expect ~100% download\n"
            "    failure. Re-run DiscordChatExporter with --media to\n"
            "    bake the images locally before retrying."
        )

    # ─── Filter against already-ingested ──
    print(f"  checking what's already in pipeline_image_candidates …")
    already = existing_source_ids(supabase, [a.source_id for a in atts])
    fresh = [a for a in atts if a.source_id not in already]
    print(f"  already ingested:          {len(already):,}")
    print(f"  new this run:              {len(fresh):,}")

    if args.limit:
        fresh = fresh[:args.limit]
        print(f"  --limit cap:               {len(fresh):,}")

    if args.dry_run:
        # Show channel breakdown so the user can sanity-check the scope
        print("\n  by channel (first 5):")
        from collections import Counter
        c = Counter(a.channel_name for a in fresh)
        for name, n in c.most_common():
            print(f"    {name:40s} {n:>5,d}")
        print("\nDRY RUN — nothing downloaded or inserted.")
        return

    # ─── Download in parallel ──
    print(f"\ndownloading {len(fresh):,} attachments (concurrency={DOWNLOAD_WORKERS}) …")
    results: list[tuple[Attachment, bytes, str]] = []
    expired_or_failed = 0
    with ThreadPoolExecutor(max_workers=DOWNLOAD_WORKERS) as ex:
        futs = {ex.submit(download_one, a): a for a in fresh}
        done = 0
        for fut in as_completed(futs):
            done += 1
            res = fut.result()
            if res is None:
                expired_or_failed += 1
            else:
                results.append(res)
            if done % 100 == 0 or done == len(fresh):
                print(f"  [{done:>5d}/{len(fresh)}] ok={len(results)} expired/failed={expired_or_failed}")

    # ─── Dedupe by md5 — same photo posted in multiple channels ──
    by_md5: dict[str, tuple[Attachment, bytes, str]] = {}
    for r in results:
        by_md5.setdefault(r[2], r)
    print(f"\nunique by md5:               {len(by_md5):,}  (collapsed {len(results)-len(by_md5)} reposts)")

    # ─── Upload to R2 + insert candidate row ──
    inserted, skipped, errors = 0, 0, 0
    for md5, (att, body, _) in by_md5.items():
        ext = att.file_ext if att.file_ext != ".heic" else ".heic"
        r2_key = f"{CDN_STAGING_PREFIX}/{md5[:2]}/{md5}{ext}"
        try:
            try:
                r2.head_object(Bucket=bucket, Key=r2_key)
            except r2.exceptions.ClientError:
                r2.put_object(
                    Bucket=bucket,
                    Key=r2_key,
                    Body=body,
                    ContentType=content_type_for(ext),
                )

            supabase.table("pipeline_image_candidates").upsert({
                "source": "discord",
                "source_url": att.url,
                "source_id": att.source_id,
                "source_metadata": {
                    "channel_name": att.channel_name,
                    "channel_id":   att.channel_id,
                    "message_id":   att.message_id,
                    "attachment_id": att.attachment_id,
                    "file_name":    att.file_name,
                    "timestamp":    att.timestamp,
                    "declared_size": att.declared_size,
                },
                "target_boba_id":     None,   # unknown until Stage B
                "target_card_number": None,
                "raw_image_r2_key":   r2_key,
                "crop_image_r2_key":  r2_key,
                "image_md5":          md5,
                "state":              "cropped",
                "scraped_by_run_id":  run_id,
            }, on_conflict="source,source_id", ignore_duplicates=True).execute()
            inserted += 1
        except Exception as e:
            print(f"    ! failed for {att.source_id}: {e}")
            errors += 1

        if (inserted + errors) % 100 == 0:
            print(f"  [{inserted+errors:>5d}/{len(by_md5)}] inserted={inserted} errors={errors}")

    print(f"\n--- summary ---")
    print(f"  attachments scanned:       {len(atts):,}")
    print(f"  already ingested:          {len(already):,}")
    print(f"  attempted:                 {len(fresh):,}")
    print(f"  download failed/expired:   {expired_or_failed:,}")
    print(f"  unique by md5:             {len(by_md5):,}")
    print(f"  inserted:                  {inserted:,}")
    print(f"  errors:                    {errors:,}")

    if run_id:
        supabase.table("pipeline_runs").update({
            "finished_at": "now()",
            "candidates_processed": len(fresh),
            "candidates_accepted":  inserted,
            "errors_encountered":   errors + expired_or_failed,
            "summary": {
                "source": "discord-export",
                "scanned": len(atts),
                "already_ingested": len(already),
                "attempted": len(fresh),
                "expired_or_failed": expired_or_failed,
                "unique_by_md5": len(by_md5),
                "inserted": inserted,
                "errors": errors,
            },
        }).eq("id", run_id).execute()


if __name__ == "__main__":
    main()
