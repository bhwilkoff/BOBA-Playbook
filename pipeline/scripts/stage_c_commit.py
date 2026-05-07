#!/usr/bin/env python3
"""
stage_c_commit.py — Stage C commit + cards.json update

Reads state='accepted' candidates from Supabase, picks the winner per
recognized_boba_id (highest score — "one image per card"), runs the
DECISIONS.md #026 collision guard, generates full + thumb WebP tiers,
uploads to R2, patches the catalog bundles, and opens a PR.

Designed to run from a Linux GitHub Actions workflow after Stage B
completes. Shells out to `gh pr create` for PR opening; auto-merge is
handled by the workflow YAML, not this script.

USAGE
─────
    python pipeline/scripts/stage_c_commit.py \\
        --repo-root . \\
        --branch    pipeline/auto-merge-$(date +%Y%m%d-%H%M%S)

ENV (required):
    SUPABASE_URL, SUPABASE_SERVICE_KEY
    R2_ACCOUNT_ID, R2_ACCESS_KEY, R2_SECRET_KEY
    R2_BUCKET (default: boba-card-images)
    GITHUB_TOKEN  (set by GH Actions automatically)

STATE TRANSITIONS
─────────────────
This run, per accepted candidate:
    accepted → committed   (winning candidate, image shipped to R2 + catalog)
    accepted → superseded  (lost the per-bobaId tournament — keep row for audit)
    accepted → collision   (md5 matches another accepted candidate's bytes
                            for a different bobaId — hard stop)

The 'committed' rows feed send_audit_email.py via the run record's
summary JSON.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import subprocess
import sys
import time
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import boto3
from botocore.config import Config
from dotenv import load_dotenv
from PIL import Image
from supabase import Client, create_client

# Auto-load .env from repo root for local invocation parity with CI.
load_dotenv(Path(__file__).resolve().parents[2] / ".env")


# ─── Paths inside the repo ────────────────────────────────────────────────

# Updated by this script (in-place patches setting imageFile +
# imageAvailable for each newly-shipped bobaId)
CATALOG_BUNDLES = [
    "assets/data/cards.json",
    "assets/data/cards-slim.json",
    "assets/data/cards-head.json",
    "BOBAPlaybook/display-cards.json",
    "BOBAPlaybook/cards-head.json",
]

# Image generation parameters (match DECISIONS.md #008)
FULL_MAX_DIM     = 1200
FULL_QUALITY     = 75
THUMB_MAX_DIM    = 200
THUMB_QUALITY    = 60


# ─── Helpers ──────────────────────────────────────────────────────────────

@dataclass
class WinningCandidate:
    candidate_id: str
    boba_id: str
    score: float
    margin: Optional[float]
    crop_image_r2_key: str
    image_md5: str
    image_file: str = ""        # filled in: canonical filename for R2
    full_r2_key: str = ""
    thumb_r2_key: str = ""


def make_r2_client(account_id, access_key, secret_key):
    return boto3.client(
        "s3",
        endpoint_url=f"https://{account_id}.r2.cloudflarestorage.com",
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(signature_version="s3v4", retries={"max_attempts": 3}),
    )


def safe_filename_for_boba_id(boba_id: str) -> str:
    """Sanitize a bobaId into a filesystem-safe filename.

    Stage 0 of the eventual reconcile_all.py-style normalization. Phase 4
    or later may rename to the existing cardNumber_hero_element_power
    convention; for now we use the bobaId directly so the filename is
    a 1:1 invertible mapping back to the card.
    """
    out = []
    for ch in boba_id:
        if ch.isalnum() or ch in ('-', '_', '.'):
            out.append(ch)
        else:
            out.append('_')
    # bobaIds end with trailing dashes when treatment/variation are empty
    # — strip them for filename purity
    return "".join(out).rstrip('_-') + ".webp"


def fetch_accepted(supabase: Client) -> list[dict]:
    res = (supabase.table("pipeline_image_candidates")
           .select("id,recognized_boba_id,recognition_score,recognition_margin,"
                   "crop_image_r2_key,image_md5")
           .eq("state", "accepted")
           .not_.is_("recognized_boba_id", "null")
           .execute())
    return res.data or []


def pick_winners(accepted: list[dict]) -> list[WinningCandidate]:
    """One bobaId → one winning candidate (highest score). Mantra:
    one image per card. one bobaId per card."""
    by_boba: dict[str, dict] = {}
    for row in accepted:
        bid = row["recognized_boba_id"]
        cur = by_boba.get(bid)
        if cur is None or (row["recognition_score"] or 0) > (cur["recognition_score"] or 0):
            by_boba[bid] = row

    winners: list[WinningCandidate] = []
    for bid, row in by_boba.items():
        winners.append(WinningCandidate(
            candidate_id=row["id"],
            boba_id=bid,
            score=row["recognition_score"] or 0.0,
            margin=row.get("recognition_margin"),
            crop_image_r2_key=row["crop_image_r2_key"],
            image_md5=row["image_md5"] or "",
        ))
    return winners


def detect_within_pipeline_collisions(winners: list[WinningCandidate]) -> set[str]:
    """Find bobaIds whose image_md5 matches another winner's md5. Hard
    stop on these — same bytes for two different bobaIds is exactly
    what DECISIONS.md #026 forbids."""
    md5_to_bobas = defaultdict(list)
    for w in winners:
        if w.image_md5:
            md5_to_bobas[w.image_md5].append(w.boba_id)
    collisions: set[str] = set()
    for md5, bobas in md5_to_bobas.items():
        if len(bobas) > 1:
            collisions.update(bobas)
    return collisions


def generate_image_tiers(crop_bytes: bytes) -> tuple[bytes, bytes]:
    """From the cropped source bytes, produce (full_webp, thumb_webp).

    Sizing matches DECISIONS.md #008 exactly:
      • full:  ≤1200px on the longest side, WebP quality 75 (~80 KB)
      • thumb: 200px on the longest side, WebP quality 60 (~10 KB)
    """
    src = Image.open(io.BytesIO(crop_bytes)).convert("RGB")

    def resize(img: Image.Image, max_dim: int) -> Image.Image:
        w, h = img.size
        if max(w, h) <= max_dim:
            return img
        if w >= h:
            new_w = max_dim
            new_h = int(h * (max_dim / w))
        else:
            new_h = max_dim
            new_w = int(w * (max_dim / h))
        return img.resize((new_w, new_h), Image.LANCZOS)

    full_buf  = io.BytesIO()
    thumb_buf = io.BytesIO()
    resize(src, FULL_MAX_DIM ).save(full_buf,  format="WEBP", quality=FULL_QUALITY)
    resize(src, THUMB_MAX_DIM).save(thumb_buf, format="WEBP", quality=THUMB_QUALITY)
    return full_buf.getvalue(), thumb_buf.getvalue()


def upload_winner(r2, bucket: str, w: WinningCandidate, full_bytes: bytes,
                  thumb_bytes: bytes, dry_run: bool):
    if dry_run:
        return
    r2.put_object(Bucket=bucket, Key=w.full_r2_key,  Body=full_bytes,
                  ContentType="image/webp",
                  CacheControl="public, max-age=31536000, immutable")
    r2.put_object(Bucket=bucket, Key=w.thumb_r2_key, Body=thumb_bytes,
                  ContentType="image/webp",
                  CacheControl="public, max-age=31536000, immutable")


def patch_bundle(path: Path, updates: dict[str, str]) -> int:
    """Patch a cards-style JSON bundle: for each {bobaId: imageFile} in
    updates, find the matching card and set imageFile + imageAvailable.

    Returns the count of records actually patched.
    """
    if not path.exists():
        print(f"  skip {path}: not present")
        return 0
    data = json.loads(path.read_text())
    cards = data["cards"] if isinstance(data, dict) and "cards" in data else data

    patched = 0
    for c in cards:
        cn       = (c.get("cardNumber") or "").strip()
        hero     = (c.get("hero") or c.get("name") or "").strip()
        treat    = (c.get("treatment") or "").strip()
        variation = (c.get("variation") or "").strip()
        bid = f"{cn}-{hero}-{treat}-{variation}"
        if bid in updates:
            c["imageFile"] = updates[bid]
            c["imageAvailable"] = True
            patched += 1

    path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
    return patched


def update_candidates_post_commit(supabase: Client, winners: list[WinningCandidate],
                                  collisions: set[str], run_id: str,
                                  all_accepted_ids: list[str]):
    """Write back per-candidate state transitions."""
    winning_ids = {w.candidate_id for w in winners}

    for w in winners:
        new_state = "collision" if w.boba_id in collisions else "committed"
        payload = {
            "state": new_state,
            "committed_by_run_id": run_id,
        }
        if new_state == "collision":
            payload["collision_with_boba_id"] = w.boba_id
        supabase.table("pipeline_image_candidates") \
                .update(payload).eq("id", w.candidate_id).execute()

    # Lost-the-tournament rows transition to 'superseded' (kept for audit)
    losers = [cid for cid in all_accepted_ids if cid not in winning_ids]
    for cid in losers:
        supabase.table("pipeline_image_candidates") \
                .update({"state": "superseded", "committed_by_run_id": run_id}) \
                .eq("id", cid).execute()


def update_card_images_table(supabase: Client, winners: list[WinningCandidate]):
    """Mirror imageFile updates in pipeline_card_images so future runs
    can see attempt history and the canonical accepted candidate."""
    rows = [{
        "boba_id":     w.boba_id,
        "has_image":   True,
        "image_file":  w.image_file,
        "last_attempted_at": "now()",
        "accepted_candidate_id": w.candidate_id,
    } for w in winners]
    if rows:
        # Upsert by boba_id (pk). attempt_count incremented separately.
        supabase.table("pipeline_card_images") \
                .upsert(rows, on_conflict="boba_id").execute()


def open_pr(repo_root: Path, branch: str, winners: list[WinningCandidate],
            cdn_base: str, run_id: str, dry_run: bool) -> Optional[str]:
    """Commit the bundle changes on `branch` and open a PR. Returns the
    PR URL on success."""
    if dry_run:
        return None

    title = f"pipeline: ship {len(winners)} card images (run {run_id[:8]})"
    body_lines = [
        f"## Stage C run `{run_id}`",
        "",
        f"- **Winners merged:** {len(winners)}",
        f"- **R2 prefix:** `full/` + `thumbs/` on `boba-card-images`",
        "",
        "### Cards",
        "",
        "| bobaId | score | margin | thumb |",
        "|---|---|---|---|",
    ]
    for w in winners[:200]:
        thumb_url = f"{cdn_base}/thumbs/{Path(w.image_file).name}"
        body_lines.append(
            f"| `{w.boba_id}` | {w.score:.2f} | "
            f"{w.margin:.2f} | "
            f"<img src='{thumb_url}' width='80'> |"
            if w.margin is not None else
            f"| `{w.boba_id}` | {w.score:.2f} | — | "
            f"<img src='{thumb_url}' width='80'> |"
        )
    if len(winners) > 200:
        body_lines.append(f"| _+ {len(winners) - 200} more — see audit email_ | | | |")

    body = "\n".join(body_lines)

    # git operations
    def git(*cmd, check=True):
        return subprocess.run(["git", "-C", str(repo_root), *cmd],
                              check=check, capture_output=True, text=True)

    git("checkout", "-b", branch)
    git("add",
        "assets/data/cards.json",
        "assets/data/cards-slim.json",
        "assets/data/cards-head.json",
        "BOBAPlaybook/display-cards.json",
        "BOBAPlaybook/cards-head.json")

    # No-op if no actual diff (catalog patch matched zero bobaIds)
    diff = git("diff", "--cached", "--quiet", check=False)
    if diff.returncode == 0:
        print("  no catalog diff — skipping PR")
        return None

    git("commit", "-m", title)
    git("push", "-u", "origin", branch)

    pr = subprocess.run(
        ["gh", "pr", "create",
         "--title", title,
         "--body",  body,
         "--base",  "main",
         "--head",  branch],
        cwd=str(repo_root),
        check=True, capture_output=True, text=True,
    )
    return pr.stdout.strip()


# ─── Main ─────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo-root", default=".",
                    help="Path to BOBA-Playbook checkout (default: cwd)")
    ap.add_argument("--branch",
                    default=f"pipeline/auto-merge-{int(time.time())}",
                    help="Branch name for the PR")
    ap.add_argument("--cdn-base",
                    default="https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev",
                    help="R2 public CDN base URL (used for PR thumbnails)")
    ap.add_argument("--dry-run", action="store_true",
                    help="Don't upload to R2, don't open PR, don't write Supabase")
    args = ap.parse_args()

    repo_root = Path(args.repo_root).resolve()
    if not (repo_root / "assets" / "data" / "cards.json").exists():
        sys.exit(f"not a BOBA-Playbook checkout: {repo_root}")

    # ─── Env ──
    supabase = create_client(os.environ["SUPABASE_URL"],
                             os.environ["SUPABASE_SERVICE_KEY"])
    r2 = make_r2_client(os.environ["R2_ACCOUNT_ID"],
                        os.environ["R2_ACCESS_KEY"],
                        os.environ["R2_SECRET_KEY"])
    bucket = os.environ.get("R2_BUCKET", "boba-card-images")

    # ─── Open run ──
    run = supabase.table("pipeline_runs").insert({
        "run_type": "commit",
        "gh_actions_run_id":  os.environ.get("GITHUB_RUN_ID"),
        "gh_actions_run_url": (
            f"https://github.com/{os.environ.get('GITHUB_REPOSITORY','')}"
            f"/actions/runs/{os.environ.get('GITHUB_RUN_ID','')}"
            if os.environ.get("GITHUB_RUN_ID") else None
        ),
    }).execute()
    run_id = run.data[0]["id"]
    print(f"run_id: {run_id}")

    # ─── Pull accepted candidates ──
    accepted = fetch_accepted(supabase)
    print(f"queue: {len(accepted)} candidates with state='accepted'")
    if not accepted:
        supabase.table("pipeline_runs").update({
            "finished_at": "now()", "summary": {"note": "queue empty"}
        }).eq("id", run_id).execute()
        return

    # ─── Pick winners ──
    winners = pick_winners(accepted)
    print(f"winners: {len(winners)} (one per bobaId)")

    # ─── Collision detection ──
    collisions = detect_within_pipeline_collisions(winners)
    if collisions:
        print(f"  ! within-pipeline collisions detected for {len(collisions)} bobaIds")
        for bid in sorted(collisions)[:5]:
            print(f"    - {bid}")
    winners = [w for w in winners if w.boba_id not in collisions]
    print(f"  proceeding with {len(winners)} non-colliding winners")

    # ─── Generate filenames ──
    for w in winners:
        w.image_file   = safe_filename_for_boba_id(w.boba_id)
        w.full_r2_key  = f"full/{w.image_file}"
        w.thumb_r2_key = f"thumbs/{w.image_file}"

    # ─── Generate + upload tiers ──
    print(f"→ generating + uploading {len(winners)} image tiers")
    failures: list[str] = []
    for i, w in enumerate(winners):
        try:
            crop_obj = r2.get_object(Bucket=bucket, Key=w.crop_image_r2_key)
            crop_bytes = crop_obj["Body"].read()
            full_bytes, thumb_bytes = generate_image_tiers(crop_bytes)
            upload_winner(r2, bucket, w, full_bytes, thumb_bytes, args.dry_run)
        except Exception as e:
            print(f"  ! {w.boba_id}: {e}")
            failures.append(w.boba_id)
        if (i + 1) % 25 == 0:
            print(f"  {i + 1}/{len(winners)}")

    # Drop failures from winners
    winners = [w for w in winners if w.boba_id not in failures]

    # ─── Patch catalog bundles ──
    print(f"→ patching {len(CATALOG_BUNDLES)} catalog bundles")
    updates = {w.boba_id: w.image_file for w in winners}
    for rel in CATALOG_BUNDLES:
        path = repo_root / rel
        n = patch_bundle(path, updates)
        print(f"  {rel}: patched {n} records")

    # ─── Open PR (commits + push + gh pr create) ──
    if not args.dry_run:
        try:
            pr_url = open_pr(repo_root, args.branch, winners,
                             args.cdn_base, run_id, args.dry_run)
            if pr_url:
                print(f"PR: {pr_url}")
        except subprocess.CalledProcessError as e:
            print(f"  ! PR open failed:")
            print(f"    stderr: {e.stderr}")
            pr_url = None
    else:
        pr_url = None

    # ─── Update Supabase state ──
    if not args.dry_run:
        update_candidates_post_commit(
            supabase, winners, collisions, run_id,
            [r["id"] for r in accepted]
        )
        update_card_images_table(supabase, winners)

    # ─── Close run ──
    summary = {
        "winners_committed": len(winners),
        "collisions":        len(collisions),
        "upload_failures":   len(failures),
        "pr_url":            pr_url,
        # Per-card detail used by send_audit_email.py
        "merged_cards": [{
            "boba_id":  w.boba_id,
            "score":    w.score,
            "margin":   w.margin,
            "image_file": w.image_file,
        } for w in winners],
    }
    if not args.dry_run:
        supabase.table("pipeline_runs").update({
            "finished_at":          "now()",
            "candidates_processed": len(accepted),
            "candidates_accepted":  len(winners),
            "candidates_collision": len(collisions),
            "errors_encountered":   len(failures),
            "summary":              summary,
        }).eq("id", run_id).execute()

    print(f"done. winners={len(winners)}, collisions={len(collisions)}, failures={len(failures)}")


if __name__ == "__main__":
    main()
