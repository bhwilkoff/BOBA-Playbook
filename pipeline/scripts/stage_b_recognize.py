#!/usr/bin/env python3
"""
stage_b_recognize.py — Stage B Python orchestrator

Pulls candidates with state='cropped' from Supabase, downloads their
images from R2 staging, invokes the macOS Swift binary `cardreckon`,
parses the results, and writes recognition_score + recognized_boba_id
back to Supabase, transitioning state to 'recognized'.

Designed to run from a `macos-15` GitHub Actions workflow. Requires the
cardreckon binary to be built (see pipeline/recognition/CardRecognitionCLI/).

USAGE
─────
    python pipeline/scripts/stage_b_recognize.py \\
        --cardreckon     pipeline/recognition/CardRecognitionCLI/.build/release/cardreckon \\
        --cards-json     BOBAPlaybook/display-cards.json \\
        --feature-prints BOBAPlaybook/feature-prints.bin \\
        --batch-size     500 \\
        --limit          5000

ENV (required):
    SUPABASE_URL
    SUPABASE_SERVICE_KEY
    R2_ACCOUNT_ID
    R2_ACCESS_KEY
    R2_SECRET_KEY
    R2_BUCKET (default: boba-card-images)

THRESHOLDS
──────────
After receiving the cardreckon result for a candidate, transition based
on the score + margin (placeholders — Phase 4 calibrates from real data):

    score >= 0.95 AND margin >= 0.5 AND recognized_boba_id != null
        → state = 'accepted'    (queued for Stage C auto-merge)
    score >= 0.70
        → state = 'review'      (Stage C opens PR awaiting human tap)
    score <  0.70 OR recognized_boba_id == null
        → state = 'quarantined' (not surfaced; future re-evaluation)
    error != null
        → state = 'error'

These thresholds live in code (not in the schema) so calibration tweaks
ship as workflow updates without DB migrations.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import boto3
from botocore.config import Config
from dotenv import load_dotenv
from supabase import Client, create_client

# Auto-load .env from repo root so local invocations work without a
# manual `source .env`. No-op when the file is absent (CI uses GH
# Actions secrets directly, which already populate os.environ).
load_dotenv(Path(__file__).resolve().parents[2] / ".env")


# ─── Threshold configuration ──────────────────────────────────────────────

THRESHOLDS = {
    # Top candidate scored at or above this AND margin gate passed → AUTO
    "auto_score":  0.95,
    "auto_margin": 0.50,
    # Top score at or above this (but below auto) → REVIEW (PR awaits tap)
    "review_score": 0.70,
}


# ─── Helpers ──────────────────────────────────────────────────────────────

@dataclass
class Candidate:
    id: str
    state: str
    crop_image_r2_key: str
    local_path: Optional[Path] = None
    error: Optional[str] = None


def make_r2_client(account_id: str, access_key: str, secret_key: str):
    return boto3.client(
        "s3",
        endpoint_url=f"https://{account_id}.r2.cloudflarestorage.com",
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(signature_version="s3v4", retries={"max_attempts": 3}),
    )


def fetch_candidates(supabase: Client, limit: int) -> list[Candidate]:
    """Pull candidates ready for Stage B recognition.

    Order: oldest discovered first (LIFO would let recent re-imports
    cut in line). Cap at `limit` to keep job runtime predictable.
    """
    res = (supabase.table("pipeline_image_candidates")
           .select("id,state,crop_image_r2_key")
           .eq("state", "cropped")
           .not_.is_("crop_image_r2_key", "null")
           .order("discovered_at", desc=False)
           .limit(limit)
           .execute())
    return [
        Candidate(id=row["id"], state=row["state"],
                  crop_image_r2_key=row["crop_image_r2_key"])
        for row in (res.data or [])
    ]


def download_one(r2, bucket: str, candidate: Candidate, dest_dir: Path) -> Candidate:
    """Download one candidate's cropped image from R2 to dest_dir."""
    try:
        # Path-safe local name: .../{candidate-id}.{ext}
        ext = Path(candidate.crop_image_r2_key).suffix or ".jpg"
        local = dest_dir / f"{candidate.id}{ext}"
        r2.download_file(bucket, candidate.crop_image_r2_key, str(local))
        candidate.local_path = local
    except Exception as e:
        candidate.error = f"download failed: {e}"
    return candidate


def run_cardreckon(
    cardreckon_path: Path,
    cards_json_path: Path,
    feature_prints_path: Path,
    candidates: list[Candidate],
    work_dir: Path,
) -> dict[str, dict]:
    """Invoke the Swift binary on a JSONL of candidate paths; return
    a {candidate_id → result_dict} mapping.

    Candidates with `error` already set are skipped from the input
    file (their downstream state will be set to 'error' by the caller).
    """
    runnable = [c for c in candidates if c.error is None and c.local_path is not None]
    if not runnable:
        return {}

    input_file  = work_dir / "candidates.jsonl"
    output_file = work_dir / "results.jsonl"

    with input_file.open("w") as f:
        for c in runnable:
            f.write(json.dumps({"id": c.id, "image_path": str(c.local_path)}) + "\n")

    cmd = [
        str(cardreckon_path),
        "--cards-json",     str(cards_json_path),
        "--feature-prints", str(feature_prints_path),
        "--input",          str(input_file),
        "--output",         str(output_file),
    ]
    print(f"  invoking cardreckon for {len(runnable)} candidates ...")
    t0 = time.time()
    proc = subprocess.run(cmd, capture_output=True, text=True)
    elapsed = time.time() - t0

    # cardreckon writes progress to stderr; surface it for observability
    if proc.stderr:
        for line in proc.stderr.splitlines()[:25]:
            print(f"    [cardreckon stderr] {line}")

    if proc.returncode != 0:
        print(f"  ! cardreckon exited {proc.returncode}; stderr above")
        return {}

    results: dict[str, dict] = {}
    if output_file.exists():
        with output_file.open() as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                    results[obj["id"]] = obj
                except json.JSONDecodeError as e:
                    print(f"  ! result line undecodable: {e}")

    print(f"  cardreckon: {len(results)}/{len(runnable)} returned in {elapsed:.1f}s")
    return results


def classify(score: Optional[float], margin: Optional[float],
             recognized_boba_id: Optional[str], error: Optional[str]) -> str:
    """Map a recognition result to the next pipeline state."""
    if error:
        return "error"
    if score is None or recognized_boba_id is None:
        return "quarantined"
    if (score >= THRESHOLDS["auto_score"]
            and (margin is None or margin >= THRESHOLDS["auto_margin"])):
        return "accepted"
    if score >= THRESHOLDS["review_score"]:
        return "review"
    return "quarantined"


def update_candidate(supabase: Client, candidate: Candidate,
                     result: Optional[dict], run_id: str) -> str:
    """Apply Stage B output to one candidate row. Returns the new state."""
    error = candidate.error or (result.get("error") if result else None)
    score      = (result or {}).get("score")
    margin     = (result or {}).get("margin")
    recognized = (result or {}).get("recognized_boba_id")
    next_state = classify(score, margin, recognized, error)

    payload: dict = {
        "state":                  next_state,
        "recognized_by_run_id":   run_id,
        "recognition_result":     result or None,
        "recognition_score":      score,
        "recognition_margin":     margin,
        "recognized_boba_id":     recognized,
    }
    if error:
        payload["error"] = error

    supabase.table("pipeline_image_candidates") \
            .update(payload).eq("id", candidate.id).execute()
    return next_state


# ─── Main ─────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cardreckon", required=True,
                    help="Path to the compiled cardreckon binary")
    ap.add_argument("--cards-json", required=True,
                    help="Path to display-cards.json (catalog used by ScanMatching)")
    ap.add_argument("--feature-prints", required=True,
                    help="Path to feature-prints.bin (BFPI index)")
    ap.add_argument("--batch-size", type=int, default=500,
                    help="Candidates per cardreckon invocation (default 500)")
    ap.add_argument("--limit", type=int, default=5000,
                    help="Max candidates to process this run (default 5000)")
    ap.add_argument("--download-workers", type=int, default=8,
                    help="Concurrent R2 downloads (default 8)")
    args = ap.parse_args()

    cardreckon_path     = Path(args.cardreckon).resolve()
    cards_json_path     = Path(args.cards_json).resolve()
    feature_prints_path = Path(args.feature_prints).resolve()

    for label, p in [
        ("cardreckon",     cardreckon_path),
        ("cards-json",     cards_json_path),
        ("feature-prints", feature_prints_path),
    ]:
        if not p.exists():
            sys.exit(f"missing {label}: {p}")

    # ─── Env ──
    # .strip() defensively — GH Actions' env: block has been observed
    # to inject trailing whitespace into secret values, which trips
    # supabase-py's URL validator with a generic "Invalid URL" error.
    supabase_url   = os.environ["SUPABASE_URL"].strip()
    supabase_key   = os.environ["SUPABASE_SERVICE_KEY"].strip()
    r2_account_id  = os.environ["R2_ACCOUNT_ID"].strip()
    r2_access_key  = os.environ["R2_ACCESS_KEY"].strip()
    r2_secret_key  = os.environ["R2_SECRET_KEY"].strip()
    r2_bucket      = os.environ.get("R2_BUCKET", "boba-card-images").strip()

    supabase = create_client(supabase_url, supabase_key)
    r2       = make_r2_client(r2_account_id, r2_access_key, r2_secret_key)

    # ─── Open run ──
    run = (supabase.table("pipeline_runs").insert({
        "run_type": "recognize",
        "gh_actions_run_id":  os.environ.get("GITHUB_RUN_ID"),
        "gh_actions_run_url": (
            f"https://github.com/{os.environ.get('GITHUB_REPOSITORY','')}"
            f"/actions/runs/{os.environ.get('GITHUB_RUN_ID','')}"
            if os.environ.get("GITHUB_RUN_ID") else None
        ),
    }).execute())
    run_id = run.data[0]["id"]
    print(f"run_id: {run_id}")

    # ─── Fetch + download ──
    candidates = fetch_candidates(supabase, args.limit)
    print(f"queue: {len(candidates)} candidates with state='cropped'")
    if not candidates:
        print("nothing to recognize. exiting clean.")
        supabase.table("pipeline_runs").update({
            "finished_at": "now()",
            "summary": {"note": "queue empty"}
        }).eq("id", run_id).execute()
        return

    work_root = Path(tempfile.mkdtemp(prefix="stage-b-"))
    print(f"work dir: {work_root}")

    try:
        # Download all candidates in parallel (network-bound)
        print(f"→ downloading {len(candidates)} images ({args.download_workers} workers)")
        t0 = time.time()
        with ThreadPoolExecutor(max_workers=args.download_workers) as pool:
            futures = [pool.submit(download_one, r2, r2_bucket, c, work_root)
                       for c in candidates]
            for fut in as_completed(futures):
                fut.result()
        download_failures = sum(1 for c in candidates if c.error is not None)
        print(f"  downloaded {len(candidates) - download_failures}/{len(candidates)} "
              f"in {time.time() - t0:.1f}s")

        # ─── Run cardreckon in batches ──
        results: dict[str, dict] = {}
        for i in range(0, len(candidates), args.batch_size):
            shard = candidates[i:i + args.batch_size]
            shard_results = run_cardreckon(
                cardreckon_path, cards_json_path, feature_prints_path,
                shard, work_root,
            )
            results.update(shard_results)

        # ─── Update Supabase + tally ──
        counts = {"accepted": 0, "review": 0, "quarantined": 0, "error": 0}
        for c in candidates:
            new_state = update_candidate(supabase, c, results.get(c.id), run_id)
            counts[new_state] = counts.get(new_state, 0) + 1

        print(f"by state: " + ", ".join(f"{k}={v}" for k, v in counts.items()))

        # ─── Close run ──
        supabase.table("pipeline_runs").update({
            "finished_at":            "now()",
            "candidates_processed":   len(candidates),
            "candidates_accepted":    counts.get("accepted", 0),
            "candidates_review":      counts.get("review", 0),
            "candidates_quarantined": counts.get("quarantined", 0),
            "errors_encountered":     counts.get("error", 0),
            "summary":                {"thresholds": THRESHOLDS},
        }).eq("id", run_id).execute()

    finally:
        shutil.rmtree(work_root, ignore_errors=True)

    print("done.")


if __name__ == "__main__":
    main()
